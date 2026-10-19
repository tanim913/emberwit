import 'dart:isolate';

import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/engine/engine_models.dart';
import 'package:emberwit/engine/llama/cancel_flag.dart';
import 'package:emberwit/engine/llama/llama_protocol.dart';
import 'package:emberwit/engine/text/stop_sequence_matcher.dart';
import 'package:emberwit/engine/text/utf8_stream_decoder.dart';
import 'package:flutter/foundation.dart';
import 'package:llama_ffi/llama_ffi.dart';

/// Entry point of the engine worker isolate.
///
/// Commands are handled one at a time in arrival order. Cancellation goes
/// through the shared [CancelFlag], not through messages, because the worker
/// is inside a blocking native call most of the time.
void llamaWorkerMain(WorkerBootstrap bootstrap) {
  final commands = ReceivePort('llama-engine-commands');
  final worker = LlamaWorker(
    runtimeFactory: bootstrap.runtimeFactory,
    cancelFlag: NativeCancelFlag.fromAddress(bootstrap.cancelFlagAddress),
    emit: bootstrap.events.send,
  );
  commands.listen((message) {
    if (!worker.handle(message as WorkerCommand)) {
      commands.close();
      Isolate.exit();
    }
  });
  bootstrap.events.send(WorkerReady(commands.sendPort));
}

/// Executes [WorkerCommand]s against a [LlamaRuntime].
///
/// Runs inside the worker isolate. Separate from the isolate plumbing so it
/// can be tested directly with a fake runtime.
final class LlamaWorker {
  /// Creates a worker that creates its runtime lazily with [_runtimeFactory]
  /// and reports through [_emit].
  new({
    required this._runtimeFactory,
    required CancelFlag cancelFlag,
    required this._emit,
  }) : _cancel = cancelFlag;

  final LlamaRuntime Function() _runtimeFactory;
  final CancelFlag _cancel;
  final void Function(WorkerEvent event) _emit;

  LlamaRuntime? _runtime;
  ModelInfo? _model;
  int _batchSize = 512;

  /// Handles [command]. Returns `false` after a [ShutdownCommand].
  bool handle(WorkerCommand command) {
    switch (command) {
      case LoadCommand():
        _load(command);
      case GenerateCommand():
        _generate(command);
      case CountTokensCommand(:final id, :final text):
        final runtime = _runtime;
        if (runtime == null || _model == null || !runtime.isLoaded) {
          _emit(FailedEvent(id, const NoModelLoadedFailure()));
        } else {
          try {
            _emit(TokenCountEvent(id, runtime.tokenize(text).length));
          } on LlamaException catch (error) {
            _emit(
              FailedEvent(
                id,
                GenerationFailure('tokenization failed', cause: error.message),
              ),
            );
          }
        }
      case UnloadCommand():
        _runtime?.unload();
        _model = null;
        _emit(DoneEvent(command.id));
      case ShutdownCommand():
        _runtime?.dispose();
        _runtime = null;
        _model = null;
        _emit(DoneEvent(command.id));
        return false;
    }
    return true;
  }

  void _load(LoadCommand command) {
    final id = command.id;
    final LlamaRuntime runtime;
    try {
      runtime = _runtime ??= _runtimeFactory();
    } on Object catch (error) {
      _emit(
        FailedEvent(
          id,
          ModelLoadFailure(
            ModelLoadFailureReason.engineUnavailable,
            cause: error.toString(),
          ),
        ),
      );
      return;
    }

    _model = null;
    final request = command.request;
    final watch = Stopwatch()..start();
    var lastReported = -1.0;
    try {
      final meta = runtime.load(
        request.path,
        modelParams: LlamaModelParams(
          gpuLayers: command.gpuLayers,
          useMmap: request.useMmap,
        ),
        contextParams: LlamaContextParams(
          contextLength: request.contextLength,
          threads: command.threads,
          batchSize: request.batchSize,
        ),
        onProgress: (progress) {
          if (progress >= 1 || progress - lastReported >= 0.01) {
            lastReported = progress;
            _emit(LoadProgressEvent(id, progress));
          }
          return !_cancel.isSet;
        },
      );
      _batchSize = request.batchSize.clamp(1, meta.contextLength);
      final info = ModelInfo(
        path: request.path,
        description: meta.description,
        architecture: meta.architecture,
        name: meta.name,
        sizeBytes: meta.sizeBytes,
        parameterCount: meta.parameterCount,
        trainContextLength: meta.trainContextLength,
        contextLength: meta.contextLength,
        hasChatTemplate: meta.chatTemplate != null,
        chatTemplate: meta.chatTemplate,
        gpuLayers: command.gpuLayers,
        threads: command.threads,
        devices: [for (final device in runtime.devices) device.name],
      );
      _model = info;
      _emit(LoadedEvent(id, info, watch.elapsed));
    } on LlamaException catch (error) {
      _emit(
        FailedEvent(
          id,
          ModelLoadFailure(loadFailureReason(error.code), cause: error.message),
        ),
      );
    } on Object catch (error) {
      _emit(
        FailedEvent(
          id,
          ModelLoadFailure(
            ModelLoadFailureReason.unsupportedModel,
            cause: error.toString(),
          ),
        ),
      );
    }
  }

  void _generate(GenerateCommand command) {
    final id = command.id;
    final runtime = _runtime;
    final model = _model;
    if (runtime == null || model == null || !runtime.isLoaded) {
      _emit(FailedEvent(id, const NoModelLoadedFailure()));
      return;
    }
    final request = command.request;
    final watch = Stopwatch()..start();

    final String text;
    final List<int> tokens;
    try {
      text = switch (request.prompt) {
        RawPrompt(:final text) => text,
        ChatPrompt(:final turns) => runtime.applyChatTemplate([
          for (final turn in turns)
            LlamaChatMessage(role: turn.role.name, content: turn.content),
        ]),
      };
      tokens = runtime.tokenize(text);
    } on LlamaException catch (error) {
      _emit(
        FailedEvent(
          id,
          GenerationFailure(
            error.code == LlamaErrorCode.templateFailed
                ? 'chat template unavailable'
                : 'tokenization failed',
            cause: error.message,
          ),
        ),
      );
      return;
    }

    if (tokens.length >= model.contextLength) {
      _emit(
        FailedEvent(
          id,
          ContextOverflowFailure(
            promptTokens: tokens.length,
            contextLength: model.contextLength,
          ),
        ),
      );
      return;
    }

    // Throttled requests use fewer threads; never more than at load time.
    final threads = request.threads ?? model.threads;
    runtime.setThreads(threads.clamp(1, model.threads));

    final decoder = Utf8StreamDecoder();
    final matcher = StopSequenceMatcher(request.stopSequences);
    var generated = 0;
    Duration? firstToken;
    StopReason stopReason;

    void emitText(String piece) {
      if (piece.isNotEmpty) _emit(TokenEvent(id, piece));
    }

    try {
      runtime
        ..clearContext()
        ..configureSampler(samplerParams(request.sampling));
      stopReason = _prefill(runtime, tokens);
      if (stopReason != StopReason.cancelled) {
        stopReason = StopReason.maxTokens;
        while (generated < request.maxTokens) {
          if (_cancel.isSet) {
            stopReason = StopReason.cancelled;
            break;
          }
          final token = runtime.sample();
          firstToken ??= watch.elapsed;
          if (runtime.isEndOfGeneration(token)) {
            stopReason = StopReason.endOfSequence;
            break;
          }
          generated++;
          final match = matcher.add(decoder.add(runtime.tokenBytes(token)));
          emitText(match.emit);
          if (match.stopped) {
            stopReason = StopReason.stopSequence;
            break;
          }
          if (generated >= request.maxTokens) break;
          if (runtime.usedContext >= model.contextLength) {
            stopReason = StopReason.contextFull;
            break;
          }
          runtime.decode([token]);
        }
      }
    } on LlamaException catch (error) {
      if (error.code != LlamaErrorCode.contextFull) {
        _emit(
          FailedEvent(
            id,
            GenerationFailure('decode failed', cause: error.message),
          ),
        );
        return;
      }
      stopReason = StopReason.contextFull;
    } on Object catch (error) {
      _emit(
        FailedEvent(
          id,
          GenerationFailure('generation crashed', cause: error.toString()),
        ),
      );
      return;
    }

    if (stopReason != StopReason.stopSequence) {
      emitText(matcher.add(decoder.close()).emit);
      if (!matcher.stopped) emitText(matcher.flush());
    }
    final total = watch.elapsed;
    _emit(
      GenerationDoneEvent(
        id,
        GenerationStats(
          promptTokens: tokens.length,
          generatedTokens: generated,
          timeToFirstToken: firstToken ?? total,
          totalDuration: total,
          stopReason: stopReason,
        ),
      ),
    );
  }

  /// Evaluates the prompt in chunks so cancellation is noticed between
  /// chunks. Returns [StopReason.cancelled] when cancelled, otherwise
  /// [StopReason.maxTokens] as a placeholder.
  StopReason _prefill(LlamaRuntime runtime, List<int> tokens) {
    for (var start = 0; start < tokens.length; start += _batchSize) {
      if (_cancel.isSet) return StopReason.cancelled;
      final end = (start + _batchSize).clamp(0, tokens.length);
      runtime.decode(tokens.sublist(start, end));
    }
    return StopReason.maxTokens;
  }
}

/// Maps a llama.cpp error to the user facing load failure reason.
@visibleForTesting
ModelLoadFailureReason loadFailureReason(LlamaErrorCode code) => switch (code) {
  LlamaErrorCode.fileNotFound => ModelLoadFailureReason.fileNotFound,
  LlamaErrorCode.invalidFormat => ModelLoadFailureReason.invalidFormat,
  LlamaErrorCode.contextCreationFailed =>
    ModelLoadFailureReason.insufficientMemory,
  LlamaErrorCode.loadCancelled => ModelLoadFailureReason.cancelled,
  LlamaErrorCode.libraryUnavailable => ModelLoadFailureReason.engineUnavailable,
  LlamaErrorCode.modelLoadFailed ||
  LlamaErrorCode.noModelLoaded ||
  LlamaErrorCode.tokenizationFailed ||
  LlamaErrorCode.contextFull ||
  LlamaErrorCode.decodeFailed ||
  LlamaErrorCode.templateFailed => ModelLoadFailureReason.unsupportedModel,
};

/// Converts engine sampling settings to llama.cpp sampler parameters.
@visibleForTesting
LlamaSamplerParams samplerParams(SamplingSettings settings) =>
    LlamaSamplerParams(
      temperature: settings.temperature,
      topK: settings.topK,
      topP: settings.topP,
      minP: settings.minP,
      repeatPenalty: settings.repeatPenalty,
      seed: settings.seed ?? 0xFFFFFFFF,
    );
