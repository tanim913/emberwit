import 'dart:async';
import 'dart:io';

import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/logging/app_logger.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/core/utils/backup_exclusion.dart';
import 'package:emberwit/core/utils/clock.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:emberwit/features/model_manager/data/model_downloader.dart';
import 'package:emberwit/features/model_manager/data/model_file_picker.dart';
import 'package:emberwit/features/model_manager/data/model_registry.dart';
import 'package:emberwit/features/model_manager/data/model_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:llama_ffi/llama_ffi.dart' show readGgufHeader;

/// Free storage that must remain after a download or import.
const int storageSafetyBufferBytes = 1024 * 1024 * 1024;

/// Smallest file accepted as a language model import.
const int minimumImportBytes = 32 * 1024 * 1024;

/// Computes a file's SHA-256 (injectable for tests).
typedef FileHasher = Future<String> Function(String path);

/// [ModelLibrary] storing models in app private storage.
///
/// Download flow: storage pre-check, background transfer to
/// `models/.partial/<id>.part` (falling back to mirror URLs on failure),
/// SHA-256 check against the signed catalog, then an atomic rename into
/// `models/<id>.gguf`. A mismatching file is deleted. Nothing is ever loaded
/// from `.partial`.
final class ModelLibraryImpl implements ModelLibrary {
  /// Creates the library.
  new({
    required this._storage,
    required this._registry,
    required this._downloader,
    required this._picker,
    required this._deviceProfile,
    required this._engine,
    required this._wifiOnly,
    this._backupExclusion = const BackupExclusion(),
    this._hasher = sha256OfFile,
    this._clock = const SystemClock(),
    this._logger = const SilentAppLogger(),
  });

  final ModelStorage _storage;
  final ModelRegistry _registry;
  final ModelDownloader _downloader;
  final ModelFilePicker _picker;
  final DeviceProfileRepository _deviceProfile;
  final InferenceEngine _engine;
  final bool Function() _wifiOnly;
  final BackupExclusion _backupExclusion;
  final FileHasher _hasher;
  final Clock _clock;
  final AppLogger _logger;

  final StreamController<LibraryState> _changes =
      StreamController<LibraryState>.broadcast();
  StreamSubscription<TransferEvent>? _events;
  Map<String, PendingDownload> _pending = {};
  Future<void>? _initialization;

  LibraryState _state = const LibraryState();
  final Set<Future<void>> _background = {};

  /// Runs [work] in the background while keeping track of it.
  void _track(Future<void> work) {
    _background.add(work);
    unawaited(work.whenComplete(() => _background.remove(work)));
  }

  /// Completes when no background work (verification, mirror fallback,
  /// cleanup) is running. For tests and orderly shutdown.
  @visibleForTesting
  Future<void> whenIdle() async {
    while (_background.isNotEmpty) {
      await Future.wait(_background.toList());
    }
  }

  @override
  LibraryState get state => _state;

  @override
  Stream<LibraryState> get changes => _changes.stream;

  void _emit(LibraryState next) {
    _state = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  void _setDownload(DownloadState download) => _emit(
    LibraryState(
      installed: _state.installed,
      downloads: {..._state.downloads, download.modelId: download},
    ),
  );

  void _removeDownload(String modelId) => _emit(
    LibraryState(
      installed: _state.installed,
      downloads: {..._state.downloads}..remove(modelId),
    ),
  );

  @override
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    await _storage.ensureCreated();
    try {
      await _backupExclusion.exclude(_storage.modelsDirectory);
    } on Object catch (error) {
      _logger.warning('Backup exclusion failed: $error');
    }

    // Keep only records whose file still exists.
    final installed = <InstalledModel>[];
    for (final model in await _registry.readInstalled()) {
      if (_storage.modelFile(model.fileName).existsSync()) {
        installed.add(model);
      }
    }
    installed.sort((a, b) => b.installedAt.compareTo(a.installedAt));
    await _registry.writeInstalled(installed);
    _pending = await _registry.readPending();

    final downloads = <String, DownloadState>{
      for (final id in _pending.keys)
        id: DownloadState(modelId: id, phase: DownloadPhase.queued),
    };
    _emit(LibraryState(installed: installed, downloads: downloads));

    _events = _downloader.events.listen(_onTransferEvent);
    await _downloader.start();

    final active = await _downloader.active();
    final activeIds = {for (final t in active) t.modelId};
    for (final transfer in active) {
      if (!_pending.containsKey(transfer.modelId)) continue;
      _setDownload(
        DownloadState(
          modelId: transfer.modelId,
          phase: _phaseFor(transfer.status),
          progress: transfer.progress,
        ),
      );
    }
    // Downloads the downloader no longer tracks: finished while the app was
    // closed (verify now) or lost (report as failed).
    for (final id in _pending.keys.toList()) {
      if (activeIds.contains(id)) continue;
      if (_storage.partialFile(id).existsSync()) {
        _track(_verifyAndInstall(id));
      } else {
        await _fail(id, const DownloadFailure(DownloadFailureReason.network));
      }
    }
  }

  DownloadPhase _phaseFor(TransferStatus status) => switch (status) {
    TransferStatus.enqueued =>
      _wifiOnly() ? DownloadPhase.waitingForWifi : DownloadPhase.queued,
    TransferStatus.running => DownloadPhase.downloading,
    TransferStatus.paused => DownloadPhase.paused,
    TransferStatus.complete => DownloadPhase.verifying,
    TransferStatus.failed || TransferStatus.canceled => DownloadPhase.failed,
  };

  void _onTransferEvent(TransferEvent event) {
    final id = event.modelId;
    if (!_pending.containsKey(id)) return;
    final current =
        _state.downloads[id] ??
        DownloadState(modelId: id, phase: DownloadPhase.queued);
    switch (event) {
      case TransferProgress(:final progress, :final bytesPerSecond):
        if (current.phase == DownloadPhase.verifying) return;
        _setDownload(
          DownloadState(
            modelId: id,
            phase: DownloadPhase.downloading,
            progress: progress,
            bytesPerSecond: bytesPerSecond,
            remaining: event.remaining,
          ),
        );
      case TransferStatusChanged(:final status):
        switch (status) {
          case TransferStatus.complete:
            _track(_verifyAndInstall(id));
          case TransferStatus.failed:
            _track(_tryNextMirror(id));
          case TransferStatus.canceled:
            _track(_discard(id));
          case TransferStatus.enqueued ||
              TransferStatus.running ||
              TransferStatus.paused:
            _setDownload(current.copyWith(phase: _phaseFor(status)));
        }
    }
  }

  @override
  Future<Result<void>> download(CatalogEntry entry) async {
    await initialize();
    if (_state.installedModel(entry.id) != null) return const Ok(null);
    if (_pending.containsKey(entry.id)) {
      return const Err(
        DownloadFailure(DownloadFailureReason.alreadyDownloading),
      );
    }
    final profile = await _deviceProfile.refreshProfile();
    final free = profile.valueOrNull?.freeStorageBytes;
    if (free != null && free < entry.fileSizeBytes + storageSafetyBufferBytes) {
      return const Err(
        DownloadFailure(DownloadFailureReason.insufficientStorage),
      );
    }
    _pending[entry.id] = PendingDownload(entry: entry, urlIndex: 0);
    await _registry.writePending(_pending);
    _setDownload(
      DownloadState(
        modelId: entry.id,
        phase: _wifiOnly()
            ? DownloadPhase.waitingForWifi
            : DownloadPhase.queued,
      ),
    );
    final started = await _downloader.enqueue(
      modelId: entry.id,
      displayName: entry.displayName,
      url: entry.downloadUrls.first,
      wifiOnly: _wifiOnly(),
    );
    if (!started) {
      await _fail(
        entry.id,
        const DownloadFailure(DownloadFailureReason.network),
      );
      return const Err(DownloadFailure(DownloadFailureReason.network));
    }
    return const Ok(null);
  }

  Future<void> _tryNextMirror(String id) async {
    final pending = _pending[id];
    if (pending == null) return;
    final next = pending.urlIndex + 1;
    if (next >= pending.entry.downloadUrls.length) {
      await _fail(id, const DownloadFailure(DownloadFailureReason.network));
      return;
    }
    _logger.info('Download of $id failed; trying mirror $next');
    _pending[id] = PendingDownload(entry: pending.entry, urlIndex: next);
    await _registry.writePending(_pending);
    await _downloader.forget(id);
    await _deletePartial(id);
    final started = await _downloader.enqueue(
      modelId: id,
      displayName: pending.entry.displayName,
      url: pending.entry.downloadUrls[next],
      wifiOnly: _wifiOnly(),
    );
    if (!started) {
      await _fail(id, const DownloadFailure(DownloadFailureReason.network));
    }
  }

  Future<void> _verifyAndInstall(String id) async {
    final pending = _pending[id];
    if (pending == null) return;
    final entry = pending.entry;
    _setDownload(
      DownloadState(modelId: id, phase: DownloadPhase.verifying, progress: 1),
    );
    final partial = _storage.partialFile(id);
    final String hash;
    try {
      hash = await _hasher(partial.path);
    } on Object catch (error, stackTrace) {
      _logger.error('Hashing $id failed', error, stackTrace);
      await _deletePartial(id);
      await _fail(id, const DownloadFailure(DownloadFailureReason.network));
      return;
    }
    if (hash != entry.sha256.toLowerCase()) {
      _logger.warning('SHA-256 mismatch for $id; file deleted');
      await _deletePartial(id);
      await _fail(
        id,
        const DownloadFailure(DownloadFailureReason.hashMismatch),
      );
      return;
    }
    final fileName = '$id.gguf';
    // Same directory tree: an atomic rename, never a copy.
    await partial.rename(_storage.modelFile(fileName).path);
    final model = InstalledModel(
      id: id,
      displayName: entry.displayName,
      fileName: fileName,
      sizeBytes: entry.fileSizeBytes,
      sha256: hash,
      verification: ModelVerification.verified,
      catalogEntry: entry,
      installedAt: _clock.now(),
    );
    _pending.remove(id);
    await _registry.writePending(_pending);
    await _addInstalled(model);
    await _downloader.forget(id);
    _removeDownload(id);
    _logger.info('Installed $id');
  }

  Future<void> _fail(String id, AppFailure failure) async {
    _pending.remove(id);
    await _registry.writePending(_pending);
    await _downloader.forget(id);
    _setDownload(
      DownloadState(modelId: id, phase: DownloadPhase.failed, failure: failure),
    );
  }

  Future<void> _discard(String id) async {
    _pending.remove(id);
    await _registry.writePending(_pending);
    await _deletePartial(id);
    await _downloader.forget(id);
    _removeDownload(id);
  }

  Future<void> _deletePartial(String id) async {
    final partial = _storage.partialFile(id);
    if (partial.existsSync()) await partial.delete();
  }

  Future<void> _addInstalled(InstalledModel model) async {
    final installed = [
      model,
      for (final m in _state.installed)
        if (m.id != model.id) m,
    ];
    await _registry.writeInstalled(installed);
    _emit(LibraryState(installed: installed, downloads: _state.downloads));
  }

  @override
  Future<void> pause(String modelId) async {
    if (await _downloader.pause(modelId)) {
      final current = _state.downloads[modelId];
      if (current != null) {
        _setDownload(current.copyWith(phase: DownloadPhase.paused));
      }
    }
  }

  @override
  Future<void> resume(String modelId) async {
    await _downloader.resume(modelId);
  }

  @override
  Future<void> cancel(String modelId) async {
    final current = _state.downloads[modelId];
    if (current?.phase == DownloadPhase.failed) {
      // Dismiss a failed download.
      _removeDownload(modelId);
      return;
    }
    if (!await _downloader.cancel(modelId)) await _discard(modelId);
  }

  @override
  Future<Result<InstalledModel?>> importFromDevice() async {
    await initialize();
    final String? path;
    try {
      path = await _picker.pick();
    } on Object catch (error) {
      return Err(ImportFailure(ImportFailureReason.copyFailed, cause: error));
    }
    if (path == null) return const Ok(null);
    return await importFile(File(path));
  }

  /// Validates and imports [source] as an unverified model. The source file
  /// is moved when possible (the picker's private copy) and copied
  /// otherwise.
  Future<Result<InstalledModel>> importFile(File source) async {
    await initialize();
    final header = readGgufHeader(source);
    if (header == null) {
      return const Err(ImportFailure(ImportFailureReason.notGguf));
    }
    if (!header.isSupportedVersion) {
      return const Err(ImportFailure(ImportFailureReason.unsupportedVersion));
    }
    final size = source.lengthSync();
    if (size < minimumImportBytes) {
      return const Err(ImportFailure(ImportFailureReason.tooSmall));
    }
    final free =
        (await _deviceProfile.refreshProfile()).valueOrNull?.freeStorageBytes;
    if (free != null && free < size + storageSafetyBufferBytes) {
      return const Err(ImportFailure(ImportFailureReason.insufficientStorage));
    }

    final name = source.uri.pathSegments.last;
    final stem = name.toLowerCase().endsWith('.gguf')
        ? name.substring(0, name.length - 5)
        : name;
    final slug = stem
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stamp = _clock.now().millisecondsSinceEpoch.toRadixString(36);
    final base = slug.isEmpty ? 'model' : slug;
    final short = base.length > 40 ? base.substring(0, 40) : base;
    final id = 'imported-$short-$stamp';
    final fileName = '$id.gguf';
    final target = _storage.modelFile(fileName);
    final temporary = File('${_storage.partialDirectory.path}/$id.import');
    try {
      try {
        await source.rename(temporary.path);
      } on FileSystemException {
        await source.copy(temporary.path);
      }
      final hash = await _hasher(temporary.path);
      await temporary.rename(target.path);
      final model = InstalledModel(
        id: id,
        displayName: stem,
        fileName: fileName,
        sizeBytes: size,
        sha256: hash,
        verification: ModelVerification.unverified,
        installedAt: _clock.now(),
      );
      await _addInstalled(model);
      return Ok(model);
    } on Object catch (error, stackTrace) {
      _logger.error('Import failed', error, stackTrace);
      if (temporary.existsSync()) await temporary.delete();
      return Err(
        ImportFailure(
          ImportFailureReason.copyFailed,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> delete(String modelId) async {
    await initialize();
    final model = _state.installedModel(modelId);
    if (model == null) return Err(ModelNotFoundFailure(modelId));
    final path = pathOf(model);
    // Never delete the file under a loaded model.
    final stats = await _engine.getStats();
    if (stats.model?.path == path) await _engine.unloadModel();
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } on FileSystemException catch (error, stackTrace) {
      return Err(UnexpectedFailure(cause: error, stackTrace: stackTrace));
    }
    final installed = [
      for (final m in _state.installed)
        if (m.id != modelId) m,
    ];
    await _registry.writeInstalled(installed);
    _emit(LibraryState(installed: installed, downloads: _state.downloads));
    return const Ok(null);
  }

  @override
  String pathOf(InstalledModel model) =>
      _storage.modelFile(model.fileName).path;

  /// Stops listening to the downloader.
  Future<void> dispose() async {
    await _events?.cancel();
    await _changes.close();
  }
}
