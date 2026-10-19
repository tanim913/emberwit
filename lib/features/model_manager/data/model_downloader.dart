import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:emberwit/features/model_manager/data/model_storage.dart';
import 'package:flutter/foundation.dart';

/// Status of a transfer as reported by the downloader.
enum TransferStatus {
  /// Waiting to start (network, Wi-Fi constraint or queue).
  enqueued,

  /// Transferring.
  running,

  /// Paused.
  paused,

  /// Finished; the partial file is complete.
  complete,

  /// Failed after retries.
  failed,

  /// Cancelled.
  canceled,
}

/// An update about the transfer of model [modelId].
@immutable
sealed class TransferEvent {
  const new(this.modelId);

  /// Model being transferred.
  final String modelId;
}

/// Progress of a running transfer.
final class TransferProgress extends TransferEvent {
  /// Creates the event.
  const new(
    super.modelId, {
    required this.progress,
    this.bytesPerSecond,
    this.remaining,
  });

  /// Fraction done, 0 to 1.
  final double progress;

  /// Speed, when known.
  final double? bytesPerSecond;

  /// Time left, when known.
  final Duration? remaining;
}

/// A transfer changed status.
final class TransferStatusChanged extends TransferEvent {
  /// Creates the event.
  const new(super.modelId, this.status, {this.httpStatus});

  /// New status.
  final TransferStatus status;

  /// HTTP status of a failed response, when there was one.
  final int? httpStatus;
}

/// A transfer the downloader still knows about after a restart.
@immutable
final class ActiveTransfer {
  /// Creates the record.
  const new({
    required this.modelId,
    required this.status,
    required this.progress,
  });

  /// Model being transferred.
  final String modelId;

  /// Last known status.
  final TransferStatus status;

  /// Last known progress.
  final double progress;
}

/// Text shown in download notifications. Placeholders `{displayName}` and
/// `{progress}` are filled in by the downloader.
@immutable
final class DownloadNotificationTexts {
  /// Creates the texts.
  const new({
    required this.running,
    required this.complete,
    required this.error,
    required this.paused,
  });

  /// While downloading.
  final String running;

  /// After finishing.
  final String complete;

  /// After failing.
  final String error;

  /// While paused.
  final String paused;
}

/// Transfers model files in the background, resuming across app restarts.
abstract interface class ModelDownloader {
  /// Transfer updates.
  Stream<TransferEvent> get events;

  /// Starts the downloader: restores tracked transfers and replays updates
  /// that happened while the app was not running. Subscribe to [events]
  /// first.
  Future<void> start();

  /// Transfers the downloader still tracks.
  Future<List<ActiveTransfer>> active();

  /// Starts downloading [url] to the partial file of [modelId].
  Future<bool> enqueue({
    required String modelId,
    required String displayName,
    required String url,
    required bool wifiOnly,
  });

  /// Pauses a transfer.
  Future<bool> pause(String modelId);

  /// Resumes a paused transfer.
  Future<bool> resume(String modelId);

  /// Cancels a transfer.
  Future<bool> cancel(String modelId);

  /// Forgets a finished transfer.
  Future<void> forget(String modelId);
}

/// [ModelDownloader] on package:background_downloader: platform download
/// services that keep running when the app is in the background, resume
/// from the last byte and survive restarts. Android runs model downloads
/// as a foreground service with a progress notification (required for
/// transfers longer than 9 minutes); iOS uses background URL sessions.
final class BackgroundModelDownloader implements ModelDownloader {
  /// Creates the downloader.
  new({required this.notificationTexts, FileDownloader? downloader})
    : _downloader = downloader ?? FileDownloader();

  /// Notification texts, in the user's language.
  final DownloadNotificationTexts notificationTexts;

  final FileDownloader _downloader;

  /// Task group of model downloads.
  static const String group = 'models';

  static String _taskId(String modelId) => 'model:$modelId';

  static String? _modelId(Task task) =>
      task.taskId.startsWith('model:') ? task.taskId.substring(6) : null;

  late final Stream<TransferEvent> _events = _downloader.updates
      .map(eventFor)
      .where((e) => e != null)
      .cast<TransferEvent>()
      .asBroadcastStream();

  @override
  Stream<TransferEvent> get events => _events;

  /// Maps a plugin update to a [TransferEvent], `null` for other tasks.
  @visibleForTesting
  static TransferEvent? eventFor(TaskUpdate update) {
    final id = _modelId(update.task);
    if (id == null) return null;
    return switch (update) {
      TaskProgressUpdate(:final progress, :final networkSpeed) =>
        progress < 0
            ? null
            : TransferProgress(
                id,
                progress: progress.clamp(0, 1),
                bytesPerSecond: networkSpeed > 0 ? networkSpeed * 1e6 : null,
                remaining: update.hasTimeRemaining
                    ? update.timeRemaining
                    : null,
              ),
      TaskStatusUpdate(:final status, :final responseStatusCode) =>
        TransferStatusChanged(
          id,
          statusFor(status),
          httpStatus: responseStatusCode,
        ),
    };
  }

  /// Maps the plugin's task status to [TransferStatus].
  @visibleForTesting
  static TransferStatus statusFor(TaskStatus status) => switch (status) {
    TaskStatus.enqueued || TaskStatus.waitingToRetry => TransferStatus.enqueued,
    TaskStatus.running => TransferStatus.running,
    TaskStatus.paused => TransferStatus.paused,
    TaskStatus.complete => TransferStatus.complete,
    TaskStatus.failed || TaskStatus.notFound => TransferStatus.failed,
    TaskStatus.canceled => TransferStatus.canceled,
  };

  @override
  Future<void> start() async {
    await _downloader.configure(
      globalConfig: [
        // Multi-gigabyte files: never use the (small) cache directory.
        (Config.useCacheDir, Config.never),
        (Config.runInForeground, Config.always),
        (Config.excludeFromCloudBackup, Config.always),
      ],
    );
    _downloader.configureNotificationForGroup(
      group,
      running: TaskNotification('{displayName}', notificationTexts.running),
      complete: TaskNotification('{displayName}', notificationTexts.complete),
      error: TaskNotification('{displayName}', notificationTexts.error),
      paused: TaskNotification('{displayName}', notificationTexts.paused),
      progressBar: true,
    );
    await _downloader.start(autoCleanDatabase: true);
  }

  @override
  Future<List<ActiveTransfer>> active() async {
    final records = await _downloader.database.allRecordsWithStatus(
      TaskStatus.running,
    );
    final all = [
      ...records,
      ...await _downloader.database.allRecordsWithStatus(TaskStatus.enqueued),
      ...await _downloader.database.allRecordsWithStatus(TaskStatus.paused),
      ...await _downloader.database.allRecordsWithStatus(
        TaskStatus.waitingToRetry,
      ),
    ];
    return [
      for (final record in all)
        if (_modelId(record.task) case final id?)
          ActiveTransfer(
            modelId: id,
            status: statusFor(record.status),
            progress: record.progress.clamp(0, 1),
          ),
    ];
  }

  @override
  Future<bool> enqueue({
    required String modelId,
    required String displayName,
    required String url,
    required bool wifiOnly,
  }) async {
    if (Platform.isAndroid) {
      final status = await _downloader.permissions.status(
        PermissionType.notifications,
      );
      if (status != PermissionStatus.granted) {
        await _downloader.permissions.request(PermissionType.notifications);
      }
    }
    return await _downloader.enqueue(
      DownloadTask(
        taskId: _taskId(modelId),
        url: url,
        filename: ModelStorage.partialFileName(modelId),
        directory: ModelStorage.partialRelativeDirectory,
        baseDirectory: BaseDirectory.applicationSupport,
        group: group,
        displayName: displayName,
        updates: Updates.statusAndProgress,
        requiresWiFi: wifiOnly,
        allowPause: true,
        retries: 5,
      ),
    );
  }

  @override
  Future<bool> pause(String modelId) async {
    final task = await _downloader.taskForId(_taskId(modelId));
    return task is DownloadTask && await _downloader.pause(task);
  }

  @override
  Future<bool> resume(String modelId) async {
    final task =
        await _downloader.taskForId(_taskId(modelId)) ??
        (await _downloader.database.recordForId(_taskId(modelId)))?.task;
    return task is DownloadTask && await _downloader.resume(task);
  }

  @override
  Future<bool> cancel(String modelId) =>
      _downloader.cancelTaskWithId(_taskId(modelId));

  @override
  Future<void> forget(String modelId) =>
      _downloader.database.deleteRecordWithId(_taskId(modelId));
}
