import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:llama_ffi/llama_ffi.dart';

/// Scriptable [LlamaRuntime] for engine tests. Runs in any isolate.
///
/// `sample()` returns [script] tokens in order. Token bytes come from
/// [pieces] (default: the token's decimal digits followed by a space).
class FakeLlamaRuntime implements LlamaRuntime {
  new({
    this.script = const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    this.pieces = const {},
    this.eos = 0,
    this.contextLength = 256,
    this.loadError,
    this.decodeError,
    this.decodeErrorAfter = 0,
    this.templateError = false,
    this.promptTokenCount,
    this.onSample,
    this.sampleDelay = Duration.zero,
  });

  final List<int> script;
  final Map<int, List<int>> pieces;
  final int eos;
  final int contextLength;
  final LlamaErrorCode? loadError;
  final LlamaErrorCode? decodeError;
  final int decodeErrorAfter;
  final bool templateError;
  final int? promptTokenCount;
  final void Function(int sampled)? onSample;
  final Duration sampleDelay;

  final List<String> tokenized = [];
  final List<List<int>> decodes = [];
  final List<List<LlamaChatMessage>> templated = [];
  LlamaSamplerParams? samplerParams;
  LlamaContextParams? contextParams;
  LlamaModelParams? modelParams;
  bool disposed = false;
  final List<int> threadChanges = [];
  int _sampled = 0;
  int _used = 0;
  LlamaModelMetadata? _meta;

  @override
  bool get isLoaded => _meta != null;

  @override
  LlamaModelMetadata get metadata =>
      _meta ?? (throw const LlamaException(LlamaErrorCode.noModelLoaded));

  @override
  int get usedContext => _used;

  @override
  List<LlamaDevice> get devices => const [
    LlamaDevice(name: 'CPU', description: 'fake', type: LlamaDeviceType.cpu),
  ];

  @override
  LlamaModelMetadata load(
    String path, {
    required LlamaModelParams modelParams,
    required LlamaContextParams contextParams,
    bool Function(double progress)? onProgress,
  }) {
    unload();
    this.modelParams = modelParams;
    this.contextParams = contextParams;
    for (final p in [0.25, 0.5, 1.0]) {
      if (onProgress != null && !onProgress(p)) {
        throw const LlamaException(LlamaErrorCode.loadCancelled);
      }
    }
    if (loadError != null) throw LlamaException(loadError!, 'fake');
    return _meta = LlamaModelMetadata(
      description: 'fake 1M Q4',
      architecture: 'llama',
      name: 'Fake',
      sizeBytes: 1000,
      parameterCount: 1000000,
      trainContextLength: 2048,
      contextLength: contextLength,
      chatTemplate: 'chatml',
    );
  }

  @override
  void unload() {
    _meta = null;
    _used = 0;
  }

  @override
  List<int> tokenize(
    String text, {
    bool addSpecial = true,
    bool parseSpecial = true,
  }) {
    tokenized.add(text);
    final count = promptTokenCount ?? text.split(' ').length;
    return List.generate(count, (i) => 1000 + i);
  }

  @override
  Uint8List tokenBytes(int token) =>
      Uint8List.fromList(pieces[token] ?? utf8.encode('$token '));

  @override
  bool isEndOfGeneration(int token) => token == eos;

  @override
  String applyChatTemplate(
    List<LlamaChatMessage> messages, {
    bool addAssistantPrompt = true,
    String? template,
  }) {
    if (templateError) {
      throw const LlamaException(LlamaErrorCode.templateFailed);
    }
    templated.add(messages);
    return messages.map((m) => '${m.role}: ${m.content}').join(' ');
  }

  @override
  void clearContext() {
    _used = 0;
    _sampled = 0;
  }

  @override
  void decode(List<int> tokens) {
    decodes.add(tokens);
    if (decodeError != null && decodes.length > decodeErrorAfter) {
      throw LlamaException(decodeError!);
    }
    _used += tokens.length;
  }

  @override
  void configureSampler(LlamaSamplerParams params) => samplerParams = params;

  @override
  int sample() {
    if (sampleDelay > Duration.zero) sleep(sampleDelay);
    final token = _sampled < script.length ? script[_sampled] : eos;
    _sampled++;
    onSample?.call(_sampled);
    return token;
  }

  @override
  void setThreads(int threads) => threadChanges.add(threads);

  @override
  void dispose() {
    unload();
    disposed = true;
  }
}

// Top level factories: sendable to the engine's worker isolate.

LlamaRuntime fastRuntime() => FakeLlamaRuntime();

LlamaRuntime slowRuntime() => FakeLlamaRuntime(
  script: List.generate(500, (i) => i + 1),
  sampleDelay: const Duration(milliseconds: 10),
);

LlamaRuntime failingLoadRuntime() =>
    FakeLlamaRuntime(loadError: LlamaErrorCode.invalidFormat);

LlamaRuntime unavailableRuntime() =>
    throw const LlamaException(LlamaErrorCode.libraryUnavailable);

/// Kills its own isolate on the third sampled token, like a native crash
/// taking the worker down.
LlamaRuntime crashingRuntime() => FakeLlamaRuntime(
  onSample: (n) {
    if (n == 3) Isolate.exit();
  },
);
