import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llama_ffi/src/bindings/llama_bindings.dart';
import 'package:llama_ffi/src/gguf.dart';
import 'package:llama_ffi/src/llama_library.dart';
import 'package:llama_ffi/src/llama_runtime.dart';

/// [LlamaRuntime] backed by llama.cpp through `dart:ffi`.
///
/// Owns at most one model, one context and one sampler chain. All native
/// memory is released by [unload] and [dispose].
final class FfiLlamaRuntime implements LlamaRuntime {
  /// Opens the native library (see [LlamaLibrary.open]).
  new({String? libraryDirectory})
    : _llama = LlamaLibrary.open(libraryDirectory: libraryDirectory).bindings;

  final LlamaBindings _llama;

  Pointer<llama_model> _model = nullptr;
  Pointer<llama_context> _context = nullptr;
  Pointer<llama_vocab> _vocab = nullptr;
  Pointer<llama_sampler> _sampler = nullptr;
  LlamaModelMetadata? _metadata;
  int _batchSize = 0;
  int _used = 0;
  bool _disposed = false;

  // Progress callbacks run synchronously on this isolate's thread during
  // llama_model_load_from_file, so a static slot is safe.
  static bool Function(double progress)? _progressListener;

  static bool _onProgress(double progress, Pointer<Void> userData) =>
      _progressListener?.call(progress) ?? true;

  @override
  bool get isLoaded => _context != nullptr;

  @override
  LlamaModelMetadata get metadata =>
      _metadata ?? (throw const LlamaException(LlamaErrorCode.noModelLoaded));

  @override
  int get usedContext => _used;

  @override
  List<LlamaDevice> get devices {
    final count = _llama.ggml_backend_dev_count();
    return [
      for (var i = 0; i < count; i++) _device(_llama.ggml_backend_dev_get(i)),
    ];
  }

  LlamaDevice _device(Pointer<ggml_backend_device> device) => LlamaDevice(
    name: _llama.ggml_backend_dev_name(device).cast<Utf8>().toDartString(),
    description: _llama
        .ggml_backend_dev_description(device)
        .cast<Utf8>()
        .toDartString(),
    type: switch (_llama.ggml_backend_dev_type$1(device)) {
      ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU => LlamaDeviceType.cpu,
      ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU => LlamaDeviceType.gpu,
      ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU =>
        LlamaDeviceType.integratedGpu,
      ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_ACCEL =>
        LlamaDeviceType.accelerator,
      _ => LlamaDeviceType.unknown,
    },
  );

  @override
  LlamaModelMetadata load(
    String path, {
    required LlamaModelParams modelParams,
    required LlamaContextParams contextParams,
    bool Function(double progress)? onProgress,
  }) {
    _checkNotDisposed();
    unload();

    final file = File(path);
    if (!file.existsSync()) {
      throw const LlamaException(LlamaErrorCode.fileNotFound);
    }
    final header = readGgufHeader(file);
    if (header == null || !header.isSupportedVersion) {
      throw LlamaException(
        LlamaErrorCode.invalidFormat,
        header == null ? 'not a GGUF file' : 'GGUF v${header.version}',
      );
    }

    final params = _llama.llama_model_default_params()
      ..n_gpu_layers = modelParams.gpuLayers
      ..load_mode = modelParams.useMmap
          ? llama_load_mode.LLAMA_LOAD_MODE_MMAP
          : llama_load_mode.LLAMA_LOAD_MODE_NONE;
    var cancelled = false;
    if (onProgress != null) {
      _progressListener = (progress) {
        final keepGoing = onProgress(progress);
        cancelled = !keepGoing;
        return keepGoing;
      };
      params.progress_callback =
          Pointer.fromFunction<Bool Function(Float, Pointer<Void>)>(
            _onProgress,
            true,
          );
    }

    final nativePath = path.toNativeUtf8();
    try {
      _model = _llama.llama_model_load_from_file(nativePath.cast(), params);
    } finally {
      malloc.free(nativePath);
      _progressListener = null;
    }
    if (_model == nullptr) {
      throw LlamaException(
        cancelled
            ? LlamaErrorCode.loadCancelled
            : LlamaErrorCode.modelLoadFailed,
      );
    }

    final batch = contextParams.batchSize.clamp(1, contextParams.contextLength);
    final cparams = _llama.llama_context_default_params()
      ..n_ctx = contextParams.contextLength
      ..n_batch = batch
      ..n_ubatch = batch
      ..n_threads = contextParams.threads
      ..n_threads_batch = contextParams.threads
      ..no_perf = true;
    _context = _llama.llama_init_from_model(_model, cparams);
    if (_context == nullptr) {
      _llama.llama_model_free(_model);
      _model = nullptr;
      throw const LlamaException(LlamaErrorCode.contextCreationFailed);
    }
    _vocab = _llama.llama_model_get_vocab(_model);
    _batchSize = batch;
    _used = 0;
    configureSampler(const LlamaSamplerParams());
    return _metadata = _readMetadata();
  }

  LlamaModelMetadata _readMetadata() {
    final template = _llama.llama_model_chat_template(_model, nullptr);
    return LlamaModelMetadata(
      description: _readString(
        (buf, size) => _llama.llama_model_desc(_model, buf, size),
      ),
      architecture: _metaString('general.architecture'),
      name: _metaString('general.name'),
      sizeBytes: _llama.llama_model_size(_model),
      parameterCount: _llama.llama_model_n_params(_model),
      trainContextLength: _llama.llama_model_n_ctx_train(_model),
      contextLength: _llama.llama_n_ctx(_context),
      chatTemplate: template == nullptr
          ? null
          : template.cast<Utf8>().toDartString(),
    );
  }

  String _metaString(String key) {
    final nativeKey = key.toNativeUtf8();
    try {
      return _readString(
        (buf, size) => _llama.llama_model_meta_val_str(
          _model,
          nativeKey.cast(),
          buf,
          size,
        ),
      );
    } finally {
      malloc.free(nativeKey);
    }
  }

  /// Calls [read] with a buffer, growing it when the result is truncated.
  /// Returns an empty string when the value is absent (negative result).
  static String _readString(int Function(Pointer<Char> buf, int size) read) {
    var size = 256;
    while (true) {
      final buf = malloc<Char>(size);
      try {
        final n = read(buf, size);
        if (n < 0) return '';
        if (n < size) return buf.cast<Utf8>().toDartString(length: n);
        size = n + 1;
      } finally {
        malloc.free(buf);
      }
    }
  }

  @override
  void unload() {
    if (_sampler != nullptr) {
      _llama.llama_sampler_free(_sampler);
      _sampler = nullptr;
    }
    if (_context != nullptr) {
      _llama.llama_free(_context);
      _context = nullptr;
    }
    if (_model != nullptr) {
      _llama.llama_model_free(_model);
      _model = nullptr;
    }
    _vocab = nullptr;
    _metadata = null;
    _used = 0;
  }

  @override
  List<int> tokenize(
    String text, {
    bool addSpecial = true,
    bool parseSpecial = true,
  }) {
    _checkLoaded();
    final bytes = text.toNativeUtf8();
    final byteLength = bytes.length;
    var capacity = byteLength + 16;
    try {
      while (true) {
        final tokens = malloc<Int32>(capacity);
        try {
          final n = _llama.llama_tokenize(
            _vocab,
            bytes.cast(),
            byteLength,
            tokens,
            capacity,
            addSpecial,
            parseSpecial,
          );
          if (n >= 0) return List<int>.of(tokens.asTypedList(n));
          if (-n <= capacity) {
            throw const LlamaException(LlamaErrorCode.tokenizationFailed);
          }
          capacity = -n;
        } finally {
          malloc.free(tokens);
        }
      }
    } finally {
      malloc.free(bytes);
    }
  }

  @override
  Uint8List tokenBytes(int token) {
    _checkLoaded();
    var size = 64;
    while (true) {
      final buf = malloc<Char>(size);
      try {
        final n = _llama.llama_token_to_piece(
          _vocab,
          token,
          buf,
          size,
          0,
          false,
        );
        if (n >= 0) return Uint8List.fromList(buf.cast<Uint8>().asTypedList(n));
        size = -n;
      } finally {
        malloc.free(buf);
      }
    }
  }

  @override
  bool isEndOfGeneration(int token) {
    _checkLoaded();
    return _llama.llama_vocab_is_eog(_vocab, token);
  }

  @override
  String applyChatTemplate(
    List<LlamaChatMessage> messages, {
    bool addAssistantPrompt = true,
    String? template,
  }) {
    _checkLoaded();
    final templateText = template ?? _metadata?.chatTemplate;
    if (templateText == null) {
      throw const LlamaException(
        LlamaErrorCode.templateFailed,
        'model has no chat template',
      );
    }
    return using((arena) {
      final nativeTemplate = templateText.toNativeUtf8(allocator: arena);
      final chat = arena<llama_chat_message>(messages.length);
      var totalLength = templateText.length;
      for (var i = 0; i < messages.length; i++) {
        chat[i]
          ..role = messages[i].role.toNativeUtf8(allocator: arena).cast()
          ..content = messages[i].content.toNativeUtf8(allocator: arena).cast();
        totalLength += messages[i].content.length + messages[i].role.length;
      }
      var size = totalLength * 2 + 256;
      while (true) {
        final buf = malloc<Char>(size);
        try {
          final n = _llama.llama_chat_apply_template(
            nativeTemplate.cast(),
            chat,
            messages.length,
            addAssistantPrompt,
            buf,
            size,
          );
          if (n < 0) {
            throw const LlamaException(
              LlamaErrorCode.templateFailed,
              'unsupported chat template',
            );
          }
          if (n <= size) return buf.cast<Utf8>().toDartString(length: n);
          size = n;
        } finally {
          malloc.free(buf);
        }
      }
    });
  }

  @override
  void clearContext() {
    _checkLoaded();
    _llama.llama_memory_clear(_llama.llama_get_memory(_context), true);
    _llama.llama_sampler_reset(_sampler);
    _used = 0;
  }

  @override
  void setThreads(int threads) {
    _checkLoaded();
    if (threads < 1) {
      throw ArgumentError.value(threads, 'threads', 'must be at least 1');
    }
    _llama.llama_set_n_threads(_context, threads, threads);
  }

  @override
  void decode(List<int> tokens) {
    _checkLoaded();
    if (tokens.isEmpty) return;
    if (tokens.length > _batchSize) {
      throw ArgumentError.value(
        tokens.length,
        'tokens',
        'more than the batch size $_batchSize',
      );
    }
    final contextLength = metadata.contextLength;
    if (_used + tokens.length > contextLength) {
      throw LlamaException(
        LlamaErrorCode.contextFull,
        '${_used + tokens.length} > $contextLength',
      );
    }
    final buffer = malloc<Int32>(tokens.length);
    try {
      buffer.asTypedList(tokens.length).setAll(0, tokens);
      final batch = _llama.llama_batch_get_one(buffer, tokens.length);
      final result = _llama.llama_decode(_context, batch);
      if (result == 1) {
        throw const LlamaException(LlamaErrorCode.contextFull, 'no KV slot');
      }
      if (result != 0) {
        throw LlamaException(LlamaErrorCode.decodeFailed, 'code $result');
      }
      _used += tokens.length;
    } finally {
      malloc.free(buffer);
    }
  }

  @override
  void configureSampler(LlamaSamplerParams params) {
    _checkLoaded();
    if (_sampler != nullptr) _llama.llama_sampler_free(_sampler);
    final chain = _llama.llama_sampler_chain_init(
      _llama.llama_sampler_chain_default_params(),
    );
    void add(Pointer<llama_sampler> sampler) =>
        _llama.llama_sampler_chain_add(chain, sampler);

    if (params.temperature <= 0) {
      add(_llama.llama_sampler_init_greedy());
    } else {
      // top-k first: the penalty sampler is slow on the full vocabulary.
      if (params.topK > 0) add(_llama.llama_sampler_init_top_k(params.topK));
      if (params.repeatPenalty != 1.0 && params.repeatLastN != 0) {
        add(
          _llama.llama_sampler_init_penalties(
            _llama.llama_vocab_n_tokens(_vocab),
            params.repeatLastN,
            params.repeatPenalty,
            0,
            0,
          ),
        );
      }
      if (params.topP < 1.0) {
        add(_llama.llama_sampler_init_top_p(params.topP, 1));
      }
      if (params.minP > 0) {
        add(_llama.llama_sampler_init_min_p(params.minP, 1));
      }
      add(_llama.llama_sampler_init_temp(params.temperature));
      add(_llama.llama_sampler_init_dist(params.seed));
    }
    _sampler = chain;
  }

  @override
  int sample() {
    _checkLoaded();
    return _llama.llama_sampler_sample(_sampler, _context, -1);
  }

  @override
  void dispose() {
    if (_disposed) return;
    unload();
    _disposed = true;
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('FfiLlamaRuntime used after dispose');
  }

  void _checkLoaded() {
    _checkNotDisposed();
    if (!isLoaded) throw const LlamaException(LlamaErrorCode.noModelLoaded);
  }
}
