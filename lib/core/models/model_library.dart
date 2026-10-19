import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'model_library.freezed.dart';
part 'model_library.g.dart';

/// Whether a model file's integrity is confirmed.
enum ModelVerification {
  /// SHA-256 matched the signed catalog.
  verified,

  /// Imported by the user; no trusted hash to compare against.
  unverified,
}

/// A model file stored on the device.
@freezed
abstract class InstalledModel with _$InstalledModel {
  /// Creates an installed model record.
  const factory({
    /// Catalog id, or `imported-...` for imported files.
    required String id,

    /// Name shown to users.
    required String displayName,

    /// File name inside the models directory.
    required String fileName,

    /// File size in bytes.
    required int sizeBytes,

    /// SHA-256 of the file (lowercase hex).
    required String sha256,

    /// Integrity status.
    required ModelVerification verification,

    /// When it was installed.
    required DateTime installedAt,

    /// Catalog entry it was downloaded from; `null` for imports.
    CatalogEntry? catalogEntry,
  }) = _InstalledModel;

  /// Parses JSON.
  factory fromJson(Map<String, dynamic> json) => _$InstalledModelFromJson(json);

  const new _();

  /// Whether the user imported this file.
  bool get isImported => catalogEntry == null;
}

/// Phase of a model download.
enum DownloadPhase {
  /// Waiting to start.
  queued,

  /// Waiting for a Wi-Fi connection (Wi-Fi only downloads).
  waitingForWifi,

  /// Transferring.
  downloading,

  /// Paused by the user.
  paused,

  /// Checking the SHA-256 of the finished file.
  verifying,

  /// Stopped with an error; see [DownloadState.failure].
  failed,
}

/// Progress of one model download.
@immutable
final class DownloadState {
  /// Creates a state.
  const new({
    required this.modelId,
    required this.phase,
    this.progress = 0,
    this.bytesPerSecond,
    this.remaining,
    this.failure,
  });

  /// Catalog id of the model.
  final String modelId;

  /// Current phase.
  final DownloadPhase phase;

  /// Fraction downloaded, 0 to 1.
  final double progress;

  /// Current speed, when known.
  final double? bytesPerSecond;

  /// Estimated time left, when known.
  final Duration? remaining;

  /// Why the download failed, in [DownloadPhase.failed].
  final AppFailure? failure;

  /// Returns a copy with the given fields replaced.
  DownloadState copyWith({
    DownloadPhase? phase,
    double? progress,
    double? bytesPerSecond,
    Duration? remaining,
    AppFailure? failure,
  }) => DownloadState(
    modelId: modelId,
    phase: phase ?? this.phase,
    progress: progress ?? this.progress,
    bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
    remaining: remaining ?? this.remaining,
    failure: failure ?? this.failure,
  );
}

/// Snapshot of the models on the device and downloads in flight.
@immutable
final class LibraryState {
  /// Creates a snapshot.
  const new({this.installed = const [], this.downloads = const {}});

  /// Installed models, newest first.
  final List<InstalledModel> installed;

  /// Downloads by model id.
  final Map<String, DownloadState> downloads;

  /// The installed model with [id], or `null`.
  InstalledModel? installedModel(String id) {
    for (final model in installed) {
      if (model.id == id) return model;
    }
    return null;
  }

  /// Bytes used by all installed models.
  int get totalBytes => installed.fold(0, (sum, m) => sum + m.sizeBytes);
}

/// Downloads, imports, stores and deletes model files. Implemented by the
/// model_manager feature and wired in `featureBindings()`.
abstract interface class ModelLibrary {
  /// Current state.
  LibraryState get state;

  /// Emits every state change.
  Stream<LibraryState> get changes;

  /// Restores state after an app restart (installed models, downloads that
  /// continued in the background) and verifies downloads that finished
  /// while the app was not running.
  Future<void> initialize();

  /// Starts downloading [entry]. Fails early when storage is insufficient.
  Future<Result<void>> download(CatalogEntry entry);

  /// Pauses the download of [modelId].
  Future<void> pause(String modelId);

  /// Resumes the download of [modelId].
  Future<void> resume(String modelId);

  /// Cancels the download of [modelId] and removes partial data.
  Future<void> cancel(String modelId);

  /// Lets the user pick a GGUF file and imports it as an unverified model.
  /// Returns `Ok(null)` when the user cancels the picker.
  Future<Result<InstalledModel?>> importFromDevice();

  /// Deletes an installed model's file.
  Future<Result<void>> delete(String modelId);

  /// Absolute path of [model]'s file, for loading into the engine.
  String pathOf(InstalledModel model);
}

/// The model library. Overridden by `featureBindings()`.
@Riverpod(keepAlive: true)
ModelLibrary modelLibrary(Ref ref) => throw StateError(
  'modelLibraryProvider must be overridden by featureBindings().',
);
