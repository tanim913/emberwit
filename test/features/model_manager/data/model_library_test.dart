import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/utils/clock.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:emberwit/features/model_manager/data/model_downloader.dart';
import 'package:emberwit/features/model_manager/data/model_library_impl.dart';
import 'package:emberwit/features/model_manager/data/model_registry.dart';
import 'package:emberwit/features/model_manager/data/model_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/catalog_fixtures.dart';
import '../../../fixtures/device_fixtures.dart';
import '../../../helpers/fake_inference_engine.dart';
import '../../device_profiler/fakes.dart';
import '../fakes.dart';

const _content = [1, 2, 3, 4, 5];
final _goodSha = sha256.convert(_content).toString();

void main() {
  late Directory root;
  late ModelStorage storage;
  late ModelRegistry registry;
  late FakeDownloader downloader;
  late FakePicker picker;
  late FakeDeviceProfileRepository profiles;
  late FakeInferenceEngine engine;
  var wifiOnly = true;

  ModelLibraryImpl? current;

  ModelLibraryImpl library() => current = ModelLibraryImpl(
    storage: storage,
    registry: registry,
    downloader: downloader,
    picker: picker,
    deviceProfile: profiles,
    engine: engine,
    wifiOnly: () => wifiOnly,
    hasher: (path) async =>
        sha256.convert(File(path).readAsBytesSync()).toString(),
    clock: FixedClock(DateTime.utc(2026, 9, 24)),
  )..also((lib) => downloader.onIdle = lib.whenIdle);

  setUp(() {
    root = Directory.systemTemp.createTempSync('library');
    storage = ModelStorage(root);
    registry = ModelRegistry(
      registryFile: storage.registryFile,
      pendingFile: storage.pendingFile,
    );
    downloader = FakeDownloader(storage);
    picker = FakePicker();
    profiles = FakeDeviceProfileRepository(refreshed: profile());
    engine = FakeInferenceEngine();
    wifiOnly = true;
  });

  tearDown(() async {
    await current?.whenIdle();
    current = null;
    root.deleteSync(recursive: true);
  });

  group('download', () {
    test('verifies the SHA-256 and installs atomically', () async {
      final lib = library();
      await lib.initialize();
      expect(downloader.startCalled, isTrue);
      final model = entry(sha: _goodSha, size: _content.length);

      expect((await lib.download(model)).isOk, isTrue);
      expect(downloader.enqueued.single.url, model.downloadUrls.first);
      expect(downloader.enqueued.single.wifiOnly, isTrue);
      expect(
        lib.state.downloads[model.id]!.phase,
        DownloadPhase.waitingForWifi,
      );

      await downloader.send(
        TransferProgress(
          model.id,
          progress: 0.5,
          bytesPerSecond: 2000000,
          remaining: const Duration(minutes: 3),
        ),
      );
      final progress = lib.state.downloads[model.id]!;
      expect(progress.phase, DownloadPhase.downloading);
      expect(progress.progress, 0.5);
      expect(progress.bytesPerSecond, 2e6);

      await downloader.complete(model.id, _content);
      final installed = lib.state.installedModel(model.id)!;
      expect(installed.verification, ModelVerification.verified);
      expect(installed.sha256, _goodSha);
      expect(File(lib.pathOf(installed)).readAsBytesSync(), _content);
      expect(storage.partialFile(model.id).existsSync(), isFalse);
      expect(lib.state.downloads, isEmpty);
      expect(downloader.forgotten, contains(model.id));
      expect((await registry.readInstalled()).single.id, model.id);
      expect(await registry.readPending(), isEmpty);
    });

    test('deletes a file whose hash does not match', () async {
      final lib = library();
      final model = entry(sha: 'b' * 64);
      await lib.download(model);
      await downloader.complete(model.id, _content);
      final state = lib.state.downloads[model.id]!;
      expect(state.phase, DownloadPhase.failed);
      expect(
        state.failure,
        const DownloadFailure(DownloadFailureReason.hashMismatch),
      );
      expect(storage.partialFile(model.id).existsSync(), isFalse);
      expect(lib.state.installed, isEmpty);
    });

    test('falls back to the mirror, then gives up', () async {
      final lib = library();
      final model = entry(sha: _goodSha);
      await lib.download(model);
      await downloader.send(
        TransferStatusChanged(model.id, TransferStatus.failed),
      );
      expect(
        downloader.enqueued.map((e) => e.url).toList(),
        model.downloadUrls,
      );
      expect((await registry.readPending())[model.id]!.urlIndex, 1);

      await downloader.send(
        TransferStatusChanged(model.id, TransferStatus.failed),
      );
      expect(
        lib.state.downloads[model.id]!.failure,
        const DownloadFailure(DownloadFailureReason.network),
      );
    });

    test('checks free storage first', () async {
      profiles.refreshed = profile(freeStorageBytes: gib);
      final result = await library().download(entry(size: 100));
      expect(
        result.failureOrNull,
        const DownloadFailure(DownloadFailureReason.insufficientStorage),
      );
      expect(downloader.enqueued, isEmpty);
    });

    test('refuses duplicates and skips installed models', () async {
      final lib = library();
      final model = entry(sha: _goodSha, size: 5);
      await lib.download(model);
      expect(
        (await lib.download(model)).failureOrNull,
        const DownloadFailure(DownloadFailureReason.alreadyDownloading),
      );
      await downloader.complete(model.id, _content);
      expect((await lib.download(model)).isOk, isTrue);
      expect(downloader.enqueued, hasLength(1));
    });

    test('reports a download that could not be queued', () async {
      downloader.enqueueResult = false;
      wifiOnly = false;
      final lib = library();
      final result = await lib.download(entry());
      expect(result.failureOrNull, isA<DownloadFailure>());
      expect(lib.state.downloads.values.single.phase, DownloadPhase.failed);
    });

    test('pause, resume and status changes', () async {
      final lib = library();
      final model = entry();
      await lib.download(model);
      await lib.pause(model.id);
      expect(downloader.paused, [model.id]);
      expect(lib.state.downloads[model.id]!.phase, DownloadPhase.paused);
      await lib.resume(model.id);
      expect(downloader.resumed, [model.id]);
      await downloader.send(
        TransferStatusChanged(model.id, TransferStatus.running),
      );
      expect(lib.state.downloads[model.id]!.phase, DownloadPhase.downloading);
      await downloader.send(
        const TransferStatusChanged('other', TransferStatus.running),
      );
      expect(lib.state.downloads.keys, [model.id]);
    });

    test(
      'cancel removes partial data; failed downloads can be dismissed',
      () async {
        final lib = library();
        final model = entry();
        await lib.download(model);
        storage.partialFile(model.id).writeAsBytesSync([1]);
        await lib.cancel(model.id);
        await pumpEventQueue();
        await lib.whenIdle();
        expect(lib.state.downloads, isEmpty);
        expect(storage.partialFile(model.id).existsSync(), isFalse);

        downloader.cancelResult = false;
        final other = entry(id: 'other-q4', sha: 'c' * 64);
        await lib.download(other);
        await downloader.complete(other.id, _content);
        expect(lib.state.downloads[other.id]!.phase, DownloadPhase.failed);
        await lib.cancel(other.id);
        expect(lib.state.downloads, isEmpty);
      },
    );
  });

  group('restart', () {
    test(
      'verifies a download that finished while the app was closed',
      () async {
        final model = entry(sha: _goodSha, size: 5);
        await registry.writePending({
          model.id: PendingDownload(entry: model, urlIndex: 0),
        });
        await storage.ensureCreated();
        storage.partialFile(model.id).writeAsBytesSync(_content);
        final lib = library();
        await lib.initialize();
        await lib.whenIdle();
        expect(lib.state.installedModel(model.id), isNotNull);
      },
    );

    test('restores running downloads and reports lost ones', () async {
      final running = entry(id: 'running-q4');
      final lost = entry(id: 'lost-q4');
      await registry.writePending({
        running.id: PendingDownload(entry: running, urlIndex: 0),
        lost.id: PendingDownload(entry: lost, urlIndex: 0),
      });
      downloader.activeTransfers = [
        const ActiveTransfer(
          modelId: 'running-q4',
          status: TransferStatus.running,
          progress: 0.3,
        ),
      ];
      final lib = library();
      await lib.initialize();
      expect(lib.state.downloads['running-q4']!.progress, 0.3);
      expect(lib.state.downloads['lost-q4']!.phase, DownloadPhase.failed);
    });

    test('forgets installed records whose file is gone', () async {
      await registry.writeInstalled([
        InstalledModel(
          id: 'gone',
          displayName: 'Gone',
          fileName: 'gone.gguf',
          sizeBytes: 1,
          sha256: _goodSha,
          verification: ModelVerification.verified,
          installedAt: DateTime.utc(2026),
        ),
      ]);
      final lib = library();
      await lib.initialize();
      expect(lib.state.installed, isEmpty);
    });
  });

  group('import', () {
    test('returns nothing when the picker is cancelled', () async {
      expect((await library().importFromDevice()).valueOrNull, isNull);
    });

    test('imports a valid GGUF file as unverified', () async {
      final source = writeGguf('${root.path}/picked/My Model.Q4.gguf');
      picker.path = source.path;
      final lib = library();
      final imported = (await lib.importFromDevice()).valueOrNull!;
      expect(imported.verification, ModelVerification.unverified);
      expect(imported.isImported, isTrue);
      expect(imported.displayName, 'My Model.Q4');
      expect(imported.id, startsWith('imported-my-model.q4-'));
      expect(File(lib.pathOf(imported)).lengthSync(), 33 * 1024 * 1024);
      expect(source.existsSync(), isFalse, reason: 'moved, not copied');
      expect(imported.sha256, hasLength(64));
    });

    test('rejects files that are not usable models', () async {
      final lib = library();
      Future<ImportFailureReason?> reasonFor(File file) async =>
          ((await lib.importFile(file)).failureOrNull as ImportFailure?)
              ?.reason;

      final text = File('${root.path}/notes.txt')..writeAsStringSync('hello');
      expect(await reasonFor(text), ImportFailureReason.notGguf);
      expect(
        await reasonFor(writeGguf('${root.path}/v1.gguf', version: 1)),
        ImportFailureReason.unsupportedVersion,
      );
      expect(
        await reasonFor(writeGguf('${root.path}/small.gguf', size: 4096)),
        ImportFailureReason.tooSmall,
      );
      profiles.refreshed = profile(freeStorageBytes: 100);
      expect(
        await reasonFor(writeGguf('${root.path}/big.gguf')),
        ImportFailureReason.insufficientStorage,
      );
    });
  });

  group('delete', () {
    test('removes the file and unloads it from the engine', () async {
      final lib = library();
      final model = entry(sha: _goodSha, size: 5);
      await lib.download(model);
      await downloader.complete(model.id, _content);
      final installed = lib.state.installedModel(model.id)!;
      await engine
          .loadModel(LoadModelRequest(path: lib.pathOf(installed)))
          .last;
      expect((await engine.getStats()).model, isNotNull);

      expect((await lib.delete(model.id)).isOk, isTrue);
      expect(File(lib.pathOf(installed)).existsSync(), isFalse);
      expect(lib.state.installed, isEmpty);
      expect(engine.unloadCalls, 1);
    });

    test('reports unknown models', () async {
      expect(
        (await library().delete('nope')).failureOrNull,
        const ModelNotFoundFailure('nope'),
      );
    });
  });

  test('registry survives damaged files', () async {
    await storage.ensureCreated();
    storage.registryFile.writeAsStringSync('{broken');
    storage.pendingFile.writeAsStringSync('[1,2]');
    expect(await registry.readInstalled(), isEmpty);
    expect(await registry.readPending(), isEmpty);
    storage.registryFile.writeAsStringSync('[{"id": 1}]');
    expect(await registry.readInstalled(), isEmpty);
  });

  test('sha256OfFile streams large files in an isolate', () async {
    final file = File('${root.path}/data.bin')
      ..writeAsBytesSync(List.generate(9 * 1024 * 1024, (i) => i % 251));
    expect(
      await sha256OfFile(file.path),
      sha256.convert(file.readAsBytesSync()).toString(),
    );
  });
}

extension<T> on T {
  T also(void Function(T value) action) {
    action(this);
    return this;
  }
}
