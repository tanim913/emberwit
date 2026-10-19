import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';

/// User facing, localized explanation of [failure] with a suggestion of what
/// to do next.
///
/// The switch is exhaustive over the sealed [AppFailure] hierarchy, so adding
/// a failure type without a message is a compile error.
String describeFailure(
  AppLocalizations l10n,
  AppFailure failure,
) => switch (failure) {
  UnexpectedFailure() => l10n.failureUnexpected,
  ConfigurationFailure() => l10n.failureConfiguration,
  ModelLoadFailure(:final reason) => switch (reason) {
    ModelLoadFailureReason.fileNotFound => l10n.failureModelFileNotFound,
    ModelLoadFailureReason.invalidFormat => l10n.failureModelInvalidFormat,
    ModelLoadFailureReason.unsupportedModel => l10n.failureModelUnsupported,
    ModelLoadFailureReason.insufficientMemory =>
      l10n.failureModelInsufficientMemory,
    ModelLoadFailureReason.engineUnavailable => l10n.failureEngineUnavailable,
    ModelLoadFailureReason.cancelled => l10n.failureModelLoadCancelled,
  },
  NoModelLoadedFailure() => l10n.failureNoModelLoaded,
  EngineBusyFailure() => l10n.failureEngineBusy,
  ContextOverflowFailure(:final promptTokens, :final contextLength) =>
    l10n.failureContextOverflow(promptTokens, contextLength),
  GenerationFailure() => l10n.failureGeneration,
  DeviceProfilingFailure() => l10n.failureDeviceProfiling,
  BenchmarkUnavailableFailure() => l10n.failureBenchmarkUnavailable,
  CatalogFailure(:final reason) => switch (reason) {
    CatalogFailureReason.network => l10n.failureCatalogNetwork,
    CatalogFailureReason.invalidSignature =>
      l10n.failureCatalogInvalidSignature,
    CatalogFailureReason.unsupportedSchema => l10n.failureCatalogUnsupported,
    CatalogFailureReason.malformed => l10n.failureCatalogMalformed,
    CatalogFailureReason.rollback => l10n.failureCatalogRollback,
  },
  DownloadFailure(:final reason) => switch (reason) {
    DownloadFailureReason.insufficientStorage => l10n.failureDownloadStorage,
    DownloadFailureReason.network => l10n.failureDownloadNetwork,
    DownloadFailureReason.hashMismatch => l10n.failureDownloadHashMismatch,
    DownloadFailureReason.alreadyDownloading => l10n.failureDownloadAlready,
  },
  ImportFailure(:final reason) => switch (reason) {
    ImportFailureReason.notGguf => l10n.failureImportNotGguf,
    ImportFailureReason.unsupportedVersion => l10n.failureImportVersion,
    ImportFailureReason.tooSmall => l10n.failureImportTooSmall,
    ImportFailureReason.insufficientStorage => l10n.failureImportStorage,
    ImportFailureReason.copyFailed => l10n.failureImportCopy,
  },
  ModelNotFoundFailure() => l10n.failureModelNotFound,
  RuntimeLimitFailure(:final reason) => switch (reason) {
    RuntimeLimitReason.overheated => l10n.failureRuntimeOverheated,
    RuntimeLimitReason.batteryCritical => l10n.failureRuntimeBattery,
  },
  ArchiveFailure(:final reason) => switch (reason) {
    ArchiveFailureReason.weakPassphrase => l10n.failureArchiveWeakPassphrase,
    ArchiveFailureReason.wrongPassphrase => l10n.failureArchiveWrongPassphrase,
    ArchiveFailureReason.notAnArchive => l10n.failureArchiveNotArchive,
    ArchiveFailureReason.unsupportedVersion => l10n.failureArchiveVersion,
    ArchiveFailureReason.fileError => l10n.failureArchiveFile,
  },
};
