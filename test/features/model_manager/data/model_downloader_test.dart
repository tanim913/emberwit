import 'package:background_downloader/background_downloader.dart';
import 'package:emberwit/features/model_manager/data/model_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

DownloadTask _task(String id) => DownloadTask(
  taskId: id,
  url: 'https://example.org/m.gguf',
  filename: 'm.part',
);

void main() {
  test('maps every plugin status', () {
    expect(
      BackgroundModelDownloader.statusFor(TaskStatus.enqueued),
      TransferStatus.enqueued,
    );
    expect(
      BackgroundModelDownloader.statusFor(TaskStatus.waitingToRetry),
      TransferStatus.enqueued,
    );
    expect(
      BackgroundModelDownloader.statusFor(TaskStatus.running),
      TransferStatus.running,
    );
    expect(
      BackgroundModelDownloader.statusFor(TaskStatus.paused),
      TransferStatus.paused,
    );
    expect(
      BackgroundModelDownloader.statusFor(TaskStatus.complete),
      TransferStatus.complete,
    );
    expect(
      BackgroundModelDownloader.statusFor(TaskStatus.notFound),
      TransferStatus.failed,
    );
    expect(
      BackgroundModelDownloader.statusFor(TaskStatus.failed),
      TransferStatus.failed,
    );
    expect(
      BackgroundModelDownloader.statusFor(TaskStatus.canceled),
      TransferStatus.canceled,
    );
  });

  test('turns progress updates into model events', () {
    final event =
        BackgroundModelDownloader.eventFor(
              TaskProgressUpdate(
                _task('model:qwen'),
                0.25,
                1000,
                2.5,
                const Duration(minutes: 2),
              ),
            )!
            as TransferProgress;
    expect(event.modelId, 'qwen');
    expect(event.progress, 0.25);
    expect(event.bytesPerSecond, 2.5e6);
    expect(event.remaining, const Duration(minutes: 2));
  });

  test('ignores unknown speed, negative progress and other tasks', () {
    final noSpeed =
        BackgroundModelDownloader.eventFor(
              TaskProgressUpdate(_task('model:qwen'), 0.5),
            )!
            as TransferProgress;
    expect(noSpeed.bytesPerSecond, isNull);
    expect(noSpeed.remaining, isNull);
    expect(
      BackgroundModelDownloader.eventFor(
        TaskProgressUpdate(_task('model:qwen'), -1),
      ),
      isNull,
    );
    expect(
      BackgroundModelDownloader.eventFor(
        TaskStatusUpdate(_task('other'), TaskStatus.running),
      ),
      isNull,
    );
  });

  test('turns status updates into model events', () {
    final event =
        BackgroundModelDownloader.eventFor(
              TaskStatusUpdate(_task('model:qwen'), TaskStatus.failed),
            )!
            as TransferStatusChanged;
    expect(event.modelId, 'qwen');
    expect(event.status, TransferStatus.failed);
  });
}
