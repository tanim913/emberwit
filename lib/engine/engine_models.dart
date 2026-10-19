import 'package:emberwit/core/errors/app_failure.dart';
import 'package:flutter/foundation.dart';

/// State of an inference engine.
enum EngineState {
  /// No model loaded.
  idle,

  /// A model is loading.
  loading,

  /// A model is loaded and the engine is waiting for work.
  ready,

  /// Text is being generated.
  generating,
}

/// What to load and how.
@immutable
final class LoadModelRequest {
  /// Creates a request. `null` values pick device appropriate defaults.
  const new({
    required this.path,
    this.contextLength = 2048,
    this.threads,
    this.gpuLayers,
    this.batchSize = 512,
    this.useMmap = true,
  });

  /// Absolute path of a GGUF file in app private storage.
  final String path;

  /// Tokens the context window holds (prompt plus reply).
  final int contextLength;

  /// CPU threads, or `null` for the engine default.
  final int? threads;

  /// Layers offloaded to the GPU, or `null` for the platform default (all
  /// layers on Apple Metal, none on Android).
  final int? gpuLayers;

  /// Tokens evaluated per step while reading the prompt.
  final int batchSize;

  /// Memory map the weights instead of copying them into RAM.
  final bool useMmap;

  @override
  bool operator ==(Object other) =>
      other is LoadModelRequest &&
      other.path == path &&
      other.contextLength == contextLength &&
      other.threads == threads &&
      other.gpuLayers == gpuLayers &&
      other.batchSize == batchSize &&
      other.useMmap == useMmap;

  @override
  int get hashCode =>
      Object.hash(path, contextLength, threads, gpuLayers, batchSize, useMmap);
}

/// Token sampling settings.
@immutable
final class SamplingSettings {
  /// Creates settings. Defaults suit general chat.
  const new({
    this.temperature = 0.7,
    this.topP = 0.95,
    this.topK = 40,
    this.minP = 0.05,
    this.repeatPenalty = 1.1,
    this.seed,
  });

  /// Randomness. 0 means always pick the most likely token.
  final double temperature;

  /// Nucleus sampling threshold. 1.0 disables.
  final double topP;

  /// Keep only the K most likely tokens. 0 disables.
  final int topK;

  /// Minimum probability relative to the top token. 0 disables.
  final double minP;

  /// Penalty for repeating recent tokens. 1.0 disables.
  final double repeatPenalty;

  /// Fixed random seed for reproducible output, or `null` for random.
  final int? seed;

  @override
  bool operator ==(Object other) =>
      other is SamplingSettings &&
      other.temperature == temperature &&
      other.topP == topP &&
      other.topK == topK &&
      other.minP == minP &&
      other.repeatPenalty == repeatPenalty &&
      other.seed == seed;

  @override
  int get hashCode =>
      Object.hash(temperature, topP, topK, minP, repeatPenalty, seed);
}

/// Speaker of a chat turn.
enum ChatRole {
  /// Instructions that frame the conversation.
  system,

  /// The person using the app.
  user,

  /// The model.
  assistant,
}

/// One turn of a conversation.
///
/// Text only today. Vision models will add image attachments as an extra
/// optional field, so text only callers keep working unchanged.
@immutable
final class ChatTurn {
  /// Creates a turn.
  const new({required this.role, required this.content});

  /// Who is speaking.
  final ChatRole role;

  /// What was said.
  final String content;

  @override
  bool operator ==(Object other) =>
      other is ChatTurn && other.role == role && other.content == content;

  @override
  int get hashCode => Object.hash(role, content);
}

/// Input for a generation.
@immutable
sealed class Prompt {
  const new();
}

/// A prompt that is already formatted for the model, fed as is.
final class RawPrompt extends Prompt {
  /// Wraps formatted prompt [text].
  const new(this.text);

  /// Prompt text, including any control tokens the model expects.
  final String text;

  @override
  bool operator ==(Object other) => other is RawPrompt && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// A conversation formatted with the chat template embedded in the model.
final class ChatPrompt extends Prompt {
  /// Wraps conversation [turns].
  const new(this.turns);

  /// Turns in order, usually starting with a system turn.
  final List<ChatTurn> turns;

  @override
  bool operator ==(Object other) =>
      other is ChatPrompt && listEquals(other.turns, turns);

  @override
  int get hashCode => Object.hashAll(turns);
}

/// A request to generate text.
@immutable
final class GenerationRequest {
  /// Creates a request.
  const new({
    required this.prompt,
    this.sampling = const SamplingSettings(),
    this.maxTokens = 512,
    this.stopSequences = const [],
    this.threads,
  });

  /// What to continue.
  final Prompt prompt;

  /// How to pick tokens.
  final SamplingSettings sampling;

  /// Upper bound on generated tokens.
  final int maxTokens;

  /// Generation stops when the output contains any of these. The stop
  /// sequence itself is not emitted.
  final List<String> stopSequences;

  /// CPU threads for this generation, `null` for the count the model was
  /// loaded with. Lowered when the device is hot or the battery is low.
  final int? threads;
}

/// Why a generation ended.
enum StopReason {
  /// The model produced an end of sequence token.
  endOfSequence,

  /// `maxTokens` were generated.
  maxTokens,

  /// A stop sequence appeared in the output.
  stopSequence,

  /// The caller cancelled.
  cancelled,

  /// The context window filled up.
  contextFull,
}

/// Facts about the loaded model.
@immutable
final class ModelInfo {
  /// Creates model info.
  const new({
    required this.path,
    required this.description,
    required this.architecture,
    required this.name,
    required this.sizeBytes,
    required this.parameterCount,
    required this.trainContextLength,
    required this.contextLength,
    required this.hasChatTemplate,
    required this.gpuLayers,
    required this.threads,
    required this.devices,
    this.chatTemplate,
  });

  /// File the model was loaded from.
  final String path;

  /// Short engine description, for example `qwen3 0.6B Q4_K - Medium`.
  final String description;

  /// Architecture, for example `llama` or `qwen3`.
  final String architecture;

  /// Name from the file metadata, possibly empty.
  final String name;

  /// Weights size in bytes.
  final int sizeBytes;

  /// Number of parameters.
  final int parameterCount;

  /// Context length the model was trained with.
  final int trainContextLength;

  /// Context length in use.
  final int contextLength;

  /// Whether the file embeds a chat template.
  final bool hasChatTemplate;

  /// The chat template embedded in the file (Jinja source), if any.
  final String? chatTemplate;

  /// Layers offloaded to the GPU.
  final int gpuLayers;

  /// CPU threads in use.
  final int threads;

  /// Compute devices available to the engine, for example `CPU`, `MTL0`.
  final List<String> devices;
}

/// Measurements of one generation.
@immutable
final class GenerationStats {
  /// Creates stats.
  const new({
    required this.promptTokens,
    required this.generatedTokens,
    required this.timeToFirstToken,
    required this.totalDuration,
    required this.stopReason,
  });

  /// Tokens in the prompt.
  final int promptTokens;

  /// Tokens produced.
  final int generatedTokens;

  /// From request to the first generated token (prompt processing time).
  final Duration timeToFirstToken;

  /// From request to the end of generation.
  final Duration totalDuration;

  /// Why generation ended.
  final StopReason stopReason;

  /// Tokens used in the context: prompt plus output.
  int get totalTokens => promptTokens + generatedTokens;

  /// Output speed after the first token, in tokens per second.
  double get tokensPerSecond {
    final decodeMicros =
        totalDuration.inMicroseconds - timeToFirstToken.inMicroseconds;
    if (generatedTokens <= 1 || decodeMicros <= 0) return 0;
    return (generatedTokens - 1) *
        Duration.microsecondsPerSecond /
        decodeMicros;
  }

  /// Prompt processing speed in tokens per second.
  double get promptTokensPerSecond {
    final micros = timeToFirstToken.inMicroseconds;
    if (promptTokens == 0 || micros <= 0) return 0;
    return promptTokens * Duration.microsecondsPerSecond / micros;
  }
}

/// Snapshot of what the engine is doing and how it performed.
@immutable
final class EngineStats {
  /// Creates a snapshot.
  const new({
    required this.state,
    this.model,
    this.loadDuration,
    this.lastGeneration,
  });

  /// Current state.
  final EngineState state;

  /// Loaded model, if any.
  final ModelInfo? model;

  /// How long the current model took to load.
  final Duration? loadDuration;

  /// Stats of the most recent completed generation.
  final GenerationStats? lastGeneration;
}

/// Progress of `InferenceEngine.loadModel`.
@immutable
sealed class ModelLoadEvent {
  const new();
}

/// Loading advanced to [fraction] (0 to 1).
final class ModelLoadProgress extends ModelLoadEvent {
  /// Creates a progress event.
  const new(this.fraction);

  /// Portion loaded, 0 to 1.
  final double fraction;
}

/// The model is loaded. Always the last event of a successful load.
final class ModelLoaded extends ModelLoadEvent {
  /// Creates the event.
  const new(this.info, this.duration);

  /// The loaded model.
  final ModelInfo info;

  /// Time taken to load.
  final Duration duration;
}

/// Loading failed. Always the last event of a failed load.
final class ModelLoadFailed extends ModelLoadEvent {
  /// Creates the event.
  const new(this.failure);

  /// What went wrong.
  final AppFailure failure;
}

/// Output of `InferenceEngine.generate`.
@immutable
sealed class GenerationEvent {
  const new();
}

/// A piece of generated text. Pieces are complete UTF-8 characters.
final class TokenGenerated extends GenerationEvent {
  /// Creates the event.
  const new(this.text);

  /// New text to append.
  final String text;
}

/// Generation finished. Always the last event of a successful generation,
/// including a cancelled one.
final class GenerationCompleted extends GenerationEvent {
  /// Creates the event.
  const new(this.stats);

  /// Measurements.
  final GenerationStats stats;
}

/// Generation failed. Always the last event of a failed generation.
final class GenerationFailed extends GenerationEvent {
  /// Creates the event.
  const new(this.failure);

  /// What went wrong.
  final AppFailure failure;
}
