import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/engine/engine_models.dart';

export 'package:emberwit/engine/engine_models.dart';

/// Runs a language model on the device.
///
/// This is the only inference API features use. llama.cpp is one
/// implementation (`LlamaInferenceEngine`); other backends (MediaPipe, MLC,
/// desktop) implement the same interface and are swapped in with a provider
/// override.
///
/// Implementations do the heavy work off the UI isolate and never throw:
/// failures arrive as [ModelLoadFailed], [GenerationFailed] or [Err] values.
abstract interface class InferenceEngine {
  /// Current state.
  EngineState get state;

  /// Emits every state change.
  Stream<EngineState> get stateChanges;

  /// Loads a model, replacing any loaded model. Emits [ModelLoadProgress]
  /// events, then exactly one [ModelLoaded] or [ModelLoadFailed].
  Stream<ModelLoadEvent> loadModel(LoadModelRequest request);

  /// Frees the loaded model and its memory. Succeeds when nothing is loaded.
  Future<Result<void>> unloadModel();

  /// Generates text. Emits [TokenGenerated] events, then exactly one
  /// [GenerationCompleted] or [GenerationFailed]. Cancelling the stream
  /// subscription cancels generation.
  Stream<GenerationEvent> generate(GenerationRequest request);

  /// Number of tokens [text] takes with the loaded model's tokenizer
  /// (including special tokens the model adds, such as BOS). Fails with
  /// `NoModelLoadedFailure` without a model.
  Future<Result<int>> countTokens(String text);

  /// Stops the current generation or load as soon as possible. A generation
  /// then completes with [StopReason.cancelled]. Does nothing when idle.
  Future<void> cancel();

  /// Current state, loaded model and latest measurements.
  Future<EngineStats> getStats();

  /// Stops the engine and frees all resources. The engine cannot be used
  /// afterwards.
  Future<void> dispose();
}
