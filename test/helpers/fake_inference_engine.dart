import 'dart:async';

import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/engine/inference_engine.dart';

const fakeModelInfo = ModelInfo(
  path: '/models/fake.gguf',
  description: 'fake 1M Q4',
  architecture: 'llama',
  name: 'Fake',
  sizeBytes: 1000,
  parameterCount: 1000000,
  trainContextLength: 2048,
  contextLength: 2048,
  hasChatTemplate: true,
  gpuLayers: 0,
  threads: 4,
  devices: ['CPU'],
);

/// [fakeModelInfo] loaded from [path].
ModelInfo fakeModelInfoFor(String path, {int? contextLength}) => ModelInfo(
  path: path,
  description: fakeModelInfo.description,
  architecture: fakeModelInfo.architecture,
  name: fakeModelInfo.name,
  sizeBytes: fakeModelInfo.sizeBytes,
  parameterCount: fakeModelInfo.parameterCount,
  trainContextLength: fakeModelInfo.trainContextLength,
  contextLength: contextLength ?? fakeModelInfo.contextLength,
  hasChatTemplate: fakeModelInfo.hasChatTemplate,
  gpuLayers: fakeModelInfo.gpuLayers,
  threads: fakeModelInfo.threads,
  devices: fakeModelInfo.devices,
);

/// In-process [InferenceEngine] for widget tests. Emits scripted events.
class FakeInferenceEngine implements InferenceEngine {
  new({
    this.tokens = const ['Hello', ' world'],
    this.loadFailure,
    this.generationFailure,
    this.tokenDelay = Duration.zero,
    EngineState initialState = EngineState.idle,
  }) : _state = initialState;

  final List<String> tokens;
  final AppFailure? loadFailure;
  final AppFailure? generationFailure;

  /// Delay before each token; cancellation is honoured between tokens.
  final Duration tokenDelay;
  final List<LoadModelRequest> loadRequests = [];
  int unloadCalls = 0;

  /// Frees the model right after the next load completes, like a memory
  /// warning arriving between loading and generating.
  bool unloadAfterNextLoad = false;
  final _states = StreamController<EngineState>.broadcast();
  final List<GenerationRequest> requests = [];
  EngineState _state;
  ModelInfo? _model;
  bool cancelled = false;

  /// Makes [generate] throw instead of reporting a failure, like a bug.
  bool throwOnGenerate = false;

  /// Moves to [state] as if work started or finished, for supervisor tests.
  void emitState(EngineState state) => _set(state);

  void _set(EngineState s) {
    _state = s;
    _states.add(s);
  }

  @override
  EngineState get state => _state;

  @override
  Stream<EngineState> get stateChanges => _states.stream;

  @override
  Stream<ModelLoadEvent> loadModel(LoadModelRequest request) async* {
    loadRequests.add(request);
    _set(EngineState.loading);
    yield const ModelLoadProgress(0.5);
    final failure = loadFailure;
    if (failure != null) {
      _set(EngineState.idle);
      yield ModelLoadFailed(failure);
      return;
    }
    final info = fakeModelInfoFor(
      request.path,
      contextLength: request.contextLength,
    );
    _model = info;
    _set(EngineState.ready);
    yield ModelLoaded(info, const Duration(milliseconds: 120));
    if (unloadAfterNextLoad) {
      unloadAfterNextLoad = false;
      await unloadModel();
    }
  }

  @override
  Stream<GenerationEvent> generate(GenerationRequest request) async* {
    requests.add(request);
    if (throwOnGenerate) throw StateError('engine bug');
    if (_model == null) {
      yield const GenerationFailed(NoModelLoadedFailure());
      return;
    }
    _set(EngineState.generating);
    cancelled = false;
    final failure = generationFailure;
    if (failure != null) {
      _set(EngineState.ready);
      yield GenerationFailed(failure);
      return;
    }
    var generated = 0;
    for (final token in tokens) {
      if (tokenDelay > Duration.zero) await Future<void>.delayed(tokenDelay);
      if (cancelled) break;
      generated++;
      yield TokenGenerated(token);
    }
    _set(EngineState.ready);
    yield GenerationCompleted(
      GenerationStats(
        promptTokens: 5,
        generatedTokens: generated,
        timeToFirstToken: const Duration(milliseconds: 40),
        totalDuration: Duration(milliseconds: 40 + 100 * generated),
        stopReason: cancelled ? StopReason.cancelled : StopReason.endOfSequence,
      ),
    );
  }

  /// Tokens per character used by [countTokens] (4 chars ≈ 1 token).
  int Function(String text) tokenCounter = (text) => (text.length / 4).ceil();

  @override
  Future<Result<int>> countTokens(String text) async => _model == null
      ? const Err(NoModelLoadedFailure())
      : Ok(tokenCounter(text));

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<Result<void>> unloadModel() async {
    unloadCalls++;
    _model = null;
    _set(EngineState.idle);
    return const Ok(null);
  }

  @override
  Future<EngineStats> getStats() async =>
      EngineStats(state: _state, model: _model);

  @override
  Future<void> dispose() => _states.close();
}
