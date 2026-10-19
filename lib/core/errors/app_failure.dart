import 'package:flutter/foundation.dart';

/// Base type for every expected failure that crosses a layer boundary.
///
/// Domain and data layers never throw across their public API. They return a
/// `Result` whose error side is an [AppFailure]. The hierarchy is sealed so
/// presentation code that maps failures to localized messages must handle
/// every case, and the compiler flags a new subtype that is not handled.
///
/// Subtypes carry a stable machine readable [code] for logs and tests. They
/// never carry user content (chat text, file names picked by the user), so a
/// failure can always be logged safely.
@immutable
sealed class AppFailure {
  /// Creates a failure with an optional underlying [cause] and [stackTrace].
  const new({this.cause, this.stackTrace});

  /// The lower level error that produced this failure, if any. Used for debug
  /// logging only and never shown to the user.
  final Object? cause;

  /// Stack trace of [cause], when it was captured.
  final StackTrace? stackTrace;

  /// Stable identifier of the failure kind, for example `configuration`.
  String get code;

  @override
  String toString() => cause == null
      ? 'AppFailure($code)'
      : 'AppFailure($code, cause: ${cause.runtimeType})';
}

/// An error nobody anticipated. Always a bug worth fixing.
final class UnexpectedFailure extends AppFailure {
  /// Wraps an unexpected [cause].
  const new({super.cause, super.stackTrace});

  @override
  String get code => 'unexpected';
}

/// The app was built or launched with an invalid configuration, for example
/// an unknown build flavor.
final class ConfigurationFailure extends AppFailure {
  /// Creates a configuration failure described by [detail].
  const new(this.detail, {super.cause, super.stackTrace});

  /// Developer facing description of what is misconfigured.
  final String detail;

  @override
  String get code => 'configuration';

  @override
  bool operator ==(Object other) =>
      other is ConfigurationFailure && other.detail == detail;

  @override
  int get hashCode => Object.hash(code, detail);

  @override
  String toString() => 'AppFailure($code, $detail)';
}

/// Why a model could not be loaded. Drives the user facing explanation.
enum ModelLoadFailureReason {
  /// The model file is missing or unreadable.
  fileNotFound,

  /// The file is not a GGUF model this app can read.
  invalidFormat,

  /// The model could not be loaded: unsupported architecture or damaged
  /// file.
  unsupportedModel,

  /// Not enough free memory for the weights or the context.
  insufficientMemory,

  /// The inference engine is not available on this device (for example a
  /// 32-bit CPU).
  engineUnavailable,

  /// Loading was cancelled by the user.
  cancelled,
}

/// A model failed to load.
final class ModelLoadFailure extends AppFailure {
  /// Creates a load failure with a [reason].
  const new(this.reason, {super.cause, super.stackTrace});

  /// What went wrong.
  final ModelLoadFailureReason reason;

  @override
  String get code => 'model_load.${reason.name}';

  @override
  bool operator ==(Object other) =>
      other is ModelLoadFailure && other.reason == reason;

  @override
  int get hashCode => Object.hash(code, reason);
}

/// Generation was requested but no model is loaded.
final class NoModelLoadedFailure extends AppFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'no_model_loaded';

  @override
  bool operator ==(Object other) => other is NoModelLoadedFailure;

  @override
  int get hashCode => code.hashCode;
}

/// The engine is already loading a model or generating.
final class EngineBusyFailure extends AppFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'engine_busy';

  @override
  bool operator ==(Object other) => other is EngineBusyFailure;

  @override
  int get hashCode => code.hashCode;
}

/// The prompt does not fit in the model's context window.
final class ContextOverflowFailure extends AppFailure {
  /// Creates the failure for a prompt of [promptTokens] tokens.
  const new({required this.promptTokens, required this.contextLength});

  /// Tokens in the prompt.
  final int promptTokens;

  /// Tokens the context can hold.
  final int contextLength;

  @override
  String get code => 'context_overflow';

  @override
  bool operator ==(Object other) =>
      other is ContextOverflowFailure &&
      other.promptTokens == promptTokens &&
      other.contextLength == contextLength;

  @override
  int get hashCode => Object.hash(code, promptTokens, contextLength);
}

/// The engine failed while generating text.
final class GenerationFailure extends AppFailure {
  /// Creates the failure described by [detail].
  const new(this.detail, {super.cause, super.stackTrace});

  /// Developer facing description. Never contains prompt or output text.
  final String detail;

  @override
  String get code => 'generation';

  @override
  bool operator ==(Object other) =>
      other is GenerationFailure && other.detail == detail;

  @override
  int get hashCode => Object.hash(code, detail);
}

/// The device's details could not be read from the platform.
final class DeviceProfilingFailure extends AppFailure {
  /// Creates the failure described by [detail].
  const new(this.detail, {super.cause, super.stackTrace});

  /// Developer facing description.
  final String detail;

  @override
  String get code => 'device_profiling';

  @override
  bool operator ==(Object other) =>
      other is DeviceProfilingFailure && other.detail == detail;

  @override
  int get hashCode => Object.hash(code, detail);
}

/// The micro benchmark cannot run: the benchmark model is not bundled with
/// this build.
final class BenchmarkUnavailableFailure extends AppFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'benchmark_unavailable';

  @override
  bool operator ==(Object other) => other is BenchmarkUnavailableFailure;

  @override
  int get hashCode => code.hashCode;
}

/// Why the model catalog could not be used.
enum CatalogFailureReason {
  /// The catalog server could not be reached.
  network,

  /// The signature does not verify with any trusted key.
  invalidSignature,

  /// The manifest uses a newer, incompatible format.
  unsupportedSchema,

  /// The manifest is not valid JSON or misses required fields.
  malformed,

  /// The manifest is older than the one already in use.
  rollback,
}

/// The model catalog could not be downloaded or trusted.
final class CatalogFailure extends AppFailure {
  /// Creates the failure.
  const new(this.reason, {super.cause, super.stackTrace});

  /// What went wrong.
  final CatalogFailureReason reason;

  @override
  String get code => 'catalog.${reason.name}';

  @override
  bool operator ==(Object other) =>
      other is CatalogFailure && other.reason == reason;

  @override
  int get hashCode => Object.hash(code, reason);
}

/// Why a model download failed.
enum DownloadFailureReason {
  /// Not enough free storage for the file plus the safety buffer.
  insufficientStorage,

  /// The server could not be reached or the transfer broke off.
  network,

  /// The file does not match the SHA-256 in the signed catalog.
  hashMismatch,

  /// A download of this model is already running.
  alreadyDownloading,
}

/// A model download failed.
final class DownloadFailure extends AppFailure {
  /// Creates the failure.
  const new(this.reason, {super.cause, super.stackTrace});

  /// What went wrong.
  final DownloadFailureReason reason;

  @override
  String get code => 'download.${reason.name}';

  @override
  bool operator ==(Object other) =>
      other is DownloadFailure && other.reason == reason;

  @override
  int get hashCode => Object.hash(code, reason);
}

/// Why a model file could not be imported.
enum ImportFailureReason {
  /// The file is not a GGUF model.
  notGguf,

  /// The GGUF version is not supported.
  unsupportedVersion,

  /// The file is too small to be a language model.
  tooSmall,

  /// Not enough free storage to copy the file.
  insufficientStorage,

  /// Copying the file failed.
  copyFailed,
}

/// Importing a model file failed.
final class ImportFailure extends AppFailure {
  /// Creates the failure.
  const new(this.reason, {super.cause, super.stackTrace});

  /// What went wrong.
  final ImportFailureReason reason;

  @override
  String get code => 'import.${reason.name}';

  @override
  bool operator ==(Object other) =>
      other is ImportFailure && other.reason == reason;

  @override
  int get hashCode => Object.hash(code, reason);
}

/// A model id does not match any installed model.
final class ModelNotFoundFailure extends AppFailure {
  /// Creates the failure.
  const new(this.modelId);

  /// The missing id.
  final String modelId;

  @override
  String get code => 'model_not_found';

  @override
  bool operator ==(Object other) =>
      other is ModelNotFoundFailure && other.modelId == modelId;

  @override
  int get hashCode => Object.hash(code, modelId);
}

/// Why the device cannot run the model right now.
enum RuntimeLimitReason {
  /// The device is critically hot.
  overheated,

  /// The battery is nearly empty and not charging.
  batteryCritical,
}

/// A reply was not started because of the device's state.
final class RuntimeLimitFailure extends AppFailure {
  /// Creates the failure.
  const new(this.reason);

  /// What blocks generation.
  final RuntimeLimitReason reason;

  @override
  String get code => 'runtime.${reason.name}';

  @override
  bool operator ==(Object other) =>
      other is RuntimeLimitFailure && other.reason == reason;

  @override
  int get hashCode => Object.hash(code, reason);
}

/// Why a chat export or import failed.
enum ArchiveFailureReason {
  /// The passphrase is too short.
  weakPassphrase,

  /// The passphrase does not match the file (or the file was altered).
  wrongPassphrase,

  /// The file is not an Emberwit chat export.
  notAnArchive,

  /// The file was made by a newer version of the app.
  unsupportedVersion,

  /// Reading or writing the file failed.
  fileError,
}

/// Exporting or importing chats failed.
final class ArchiveFailure extends AppFailure {
  /// Creates the failure.
  const new(this.reason, {super.cause, super.stackTrace});

  /// What went wrong.
  final ArchiveFailureReason reason;

  @override
  String get code => 'archive.${reason.name}';

  @override
  bool operator ==(Object other) =>
      other is ArchiveFailure && other.reason == reason;

  @override
  int get hashCode => Object.hash(code, reason);
}
