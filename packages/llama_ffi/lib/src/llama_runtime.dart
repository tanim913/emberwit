import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

/// Error categories reported by [LlamaException].
enum LlamaErrorCode {
  /// The native llama.cpp libraries could not be loaded on this device.
  libraryUnavailable,

  /// The model file does not exist or cannot be read.
  fileNotFound,

  /// The file is not a GGUF model.
  invalidFormat,

  /// llama.cpp rejected the model: unsupported architecture, corrupt tensors
  /// or not enough memory.
  modelLoadFailed,

  /// The inference context could not be created, almost always because the
  /// KV cache for the requested context length does not fit in memory.
  contextCreationFailed,

  /// Loading was cancelled through the progress callback.
  loadCancelled,

  /// An operation that needs a model was called without one.
  noModelLoaded,

  /// Text could not be tokenized.
  tokenizationFailed,

  /// The context window has no room left for the tokens being decoded.
  contextFull,

  /// llama_decode failed.
  decodeFailed,

  /// The chat template is missing or not supported.
  templateFailed,
}

/// Failure raised by [LlamaRuntime]. Messages are developer facing and never
/// contain prompt text.
final class LlamaException implements Exception {
  /// Creates an exception of kind [code].
  const new(this.code, [this.message = '']);

  /// What went wrong.
  final LlamaErrorCode code;

  /// Developer facing detail.
  final String message;

  @override
  String toString() => message.isEmpty
      ? 'LlamaException(${code.name})'
      : 'LlamaException(${code.name}: $message)';
}

/// How to load model weights.
@immutable
final class LlamaModelParams {
  /// Creates model parameters.
  const new({this.gpuLayers = 0, this.useMmap = true});

  /// Number of layers offloaded to the GPU. 0 keeps everything on the CPU,
  /// a large value (such as 999) offloads every layer.
  final int gpuLayers;

  /// Memory map the file instead of reading it into RAM. Loading is faster and
  /// the OS can page weights out under memory pressure.
  final bool useMmap;
}

/// Inference context configuration.
@immutable
final class LlamaContextParams {
  /// Creates context parameters.
  const new({
    required this.contextLength,
    required this.threads,
    this.batchSize = 512,
  });

  /// Maximum number of tokens (prompt plus output) the context holds.
  final int contextLength;

  /// CPU threads used for decoding.
  final int threads;

  /// Maximum tokens per [LlamaRuntime.decode] call.
  final int batchSize;
}

/// Token sampling configuration.
@immutable
final class LlamaSamplerParams {
  /// Creates sampler parameters. Defaults suit general chat.
  const new({
    this.temperature = 0.7,
    this.topK = 40,
    this.topP = 0.95,
    this.minP = 0.05,
    this.repeatPenalty = 1.1,
    this.repeatLastN = 64,
    this.seed = 0xFFFFFFFF,
  });

  /// Randomness. 0 or less selects greedy decoding.
  final double temperature;

  /// Keep only the K most likely tokens. 0 disables.
  final int topK;

  /// Nucleus sampling threshold. 1.0 disables.
  final double topP;

  /// Drop tokens less likely than minP times the top token. 0 disables.
  final double minP;

  /// Penalty for repeating recent tokens. 1.0 disables.
  final double repeatPenalty;

  /// How many recent tokens the repeat penalty considers.
  final int repeatLastN;

  /// Random seed. 0xFFFFFFFF picks a random seed.
  final int seed;
}

/// One message for [LlamaRuntime.applyChatTemplate].
@immutable
final class LlamaChatMessage {
  /// Creates a message.
  const new({required this.role, required this.content});

  /// `system`, `user` or `assistant`.
  final String role;

  /// Message text.
  final String content;
}

/// Facts about a loaded model, read from GGUF metadata.
@immutable
final class LlamaModelMetadata {
  /// Creates metadata.
  const new({
    required this.description,
    required this.architecture,
    required this.name,
    required this.sizeBytes,
    required this.parameterCount,
    required this.trainContextLength,
    required this.contextLength,
    required this.chatTemplate,
  });

  /// Short llama.cpp description, for example `qwen3 0.6B Q4_K - Medium`.
  final String description;

  /// Architecture name from `general.architecture`, for example `llama`.
  final String architecture;

  /// Model name from `general.name`, or an empty string.
  final String name;

  /// Size of all weights in bytes.
  final int sizeBytes;

  /// Number of parameters.
  final int parameterCount;

  /// Context length the model was trained with.
  final int trainContextLength;

  /// Context length of the created inference context.
  final int contextLength;

  /// Chat template embedded in the file, or `null` when absent.
  final String? chatTemplate;
}

/// Kind of compute device reported by ggml.
enum LlamaDeviceType {
  /// CPU backend.
  cpu,

  /// Discrete GPU.
  gpu,

  /// Integrated GPU (most phones).
  integratedGpu,

  /// Other accelerator.
  accelerator,

  /// Unrecognised type.
  unknown,
}

/// A compute device available to llama.cpp.
@immutable
final class LlamaDevice {
  /// Creates a device description.
  const new({
    required this.name,
    required this.description,
    required this.type,
  });

  /// Backend device name, for example `CPU` or `MTL0`.
  final String name;

  /// Human readable description.
  final String description;

  /// Device kind.
  final LlamaDeviceType type;
}

/// Synchronous llama.cpp API. One loaded model and one context at a time.
///
/// Every method blocks until the native call returns. Call it only from a
/// background isolate. Methods throw [LlamaException] on failure.
abstract interface class LlamaRuntime {
  /// Whether a model and context are loaded.
  bool get isLoaded;

  /// Metadata of the loaded model.
  ///
  /// Throws [LlamaErrorCode.noModelLoaded] without a model.
  LlamaModelMetadata get metadata;

  /// Tokens currently held in the context.
  int get usedContext;

  /// Compute devices registered with ggml.
  List<LlamaDevice> get devices;

  /// Loads the GGUF model at [path] and creates an inference context,
  /// replacing any loaded model.
  ///
  /// [onProgress] receives values from 0 to 1 while weights load. Returning
  /// `false` aborts loading with [LlamaErrorCode.loadCancelled].
  LlamaModelMetadata load(
    String path, {
    required LlamaModelParams modelParams,
    required LlamaContextParams contextParams,
    bool Function(double progress)? onProgress,
  });

  /// Frees the model and context. Safe to call without a model.
  void unload();

  /// Converts [text] to tokens. [addSpecial] adds BOS/EOS as the model
  /// expects; [parseSpecial] turns control token text such as `<|im_end|>`
  /// into control tokens.
  List<int> tokenize(
    String text, {
    bool addSpecial = true,
    bool parseSpecial = true,
  });

  /// Raw UTF-8 bytes of [token]. A multi-byte character can be split across
  /// tokens, so decode the concatenated stream, not each piece.
  Uint8List tokenBytes(int token);

  /// Whether [token] ends generation (EOS, EOT and similar).
  bool isEndOfGeneration(int token);

  /// Formats [messages] with [template], or with the model's embedded chat
  /// template when [template] is null.
  String applyChatTemplate(
    List<LlamaChatMessage> messages, {
    bool addAssistantPrompt = true,
    String? template,
  });

  /// Empties the context (KV cache) and resets the sampler.
  void clearContext();

  /// Evaluates [tokens], at most `contextParams.batchSize` of them. After this
  /// call [sample] draws from the distribution following the last token.
  void decode(List<int> tokens);

  /// Replaces the sampler chain.
  void configureSampler(LlamaSamplerParams params);

  /// Changes the CPU threads used by later [decode] calls, without
  /// reloading. Fewer threads produce less heat and use less power.
  void setThreads(int threads);

  /// Samples the next token after the last [decode] and records it for the
  /// repeat penalty. The token is not evaluated; pass it to [decode].
  int sample();

  /// Releases every native resource. The runtime is unusable afterwards.
  void dispose();
}
