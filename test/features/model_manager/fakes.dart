import 'dart:async';
import 'dart:io';

import 'package:emberwit/core/catalog/catalog_repository.dart';
import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/features/model_manager/data/model_downloader.dart';
import 'package:emberwit/features/model_manager/data/model_file_picker.dart';
import 'package:emberwit/features/model_manager/data/model_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scriptable downloader: records calls, emits events on demand.
class FakeDownloader implements ModelDownloader {
  new(this.storage);

  final ModelStorage storage;
  final _events = StreamController<TransferEvent>.broadcast();
  final List<({String modelId, String url, bool wifiOnly})> enqueued = [];
  final List<String> paused = [];
  final List<String> resumed = [];
  final List<String> canceled = [];
  final List<String> forgotten = [];
  List<ActiveTransfer> activeTransfers = [];
  bool startCalled = false;
  bool enqueueResult = true;
  bool cancelResult = true;

  /// Waits for the library's background work; set by tests.
  Future<void> Function()? onIdle;

  /// Emits [event] and waits until the library has processed it.
  Future<void> send(TransferEvent event) async {
    _events.add(event);
    await pumpEventQueue();
    await onIdle?.call();
  }

  void emit(TransferEvent event) => _events.add(event);

  /// Simulates the transfer finishing with [bytes] in the partial file.
  Future<void> complete(String modelId, List<int> bytes) async {
    storage.partialFile(modelId)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    emit(TransferStatusChanged(modelId, TransferStatus.complete));
    await pumpEventQueue();
    await onIdle?.call();
  }

  @override
  Stream<TransferEvent> get events => _events.stream;

  @override
  Future<void> start() async => startCalled = true;

  @override
  Future<List<ActiveTransfer>> active() async => activeTransfers;

  @override
  Future<bool> enqueue({
    required String modelId,
    required String displayName,
    required String url,
    required bool wifiOnly,
  }) async {
    enqueued.add((modelId: modelId, url: url, wifiOnly: wifiOnly));
    return enqueueResult;
  }

  @override
  Future<bool> pause(String modelId) async {
    paused.add(modelId);
    return true;
  }

  @override
  Future<bool> resume(String modelId) async {
    resumed.add(modelId);
    return true;
  }

  @override
  Future<bool> cancel(String modelId) async {
    canceled.add(modelId);
    if (cancelResult) {
      emit(TransferStatusChanged(modelId, TransferStatus.canceled));
    }
    return cancelResult;
  }

  @override
  Future<void> forget(String modelId) async => forgotten.add(modelId);
}

class FakePicker implements ModelFilePicker {
  String? path;

  @override
  Future<String?> pick() async => path;
}

/// GGUF v3 header followed by zero padding up to [size] bytes.
File writeGguf(String path, {int size = 33 * 1024 * 1024, int version = 3}) {
  final header = <int>[
    0x47, 0x47, 0x55, 0x46, // GGUF
    version, 0, 0, 0,
    1, 0, 0, 0, 0, 0, 0, 0,
    1, 0, 0, 0, 0, 0, 0, 0,
  ];
  final file = File(path)..createSync(recursive: true);
  file.openSync(mode: FileMode.write)
    ..writeFromSync(header)
    ..truncateSync(size)
    ..closeSync();
  return file;
}

class FakeCatalogRepository implements CatalogRepository {
  new(this.snapshot, {this.refreshResult});

  CatalogSnapshot snapshot;
  Result<CatalogSnapshot>? refreshResult;

  @override
  Future<CatalogSnapshot> current() async => snapshot;

  @override
  Future<Result<CatalogSnapshot>> refresh() async =>
      refreshResult ?? Ok(snapshot);
}

/// In-memory library for presentation tests.
class FakeModelLibrary implements ModelLibrary {
  new([this._state = const LibraryState()]);

  LibraryState _state;
  final _changes = StreamController<LibraryState>.broadcast();
  final List<String> calls = [];
  AppFailure? nextFailure;

  void set(LibraryState state) {
    _state = state;
    _changes.add(state);
  }

  @override
  LibraryState get state => _state;

  @override
  Stream<LibraryState> get changes => _changes.stream;

  @override
  Future<void> initialize() async {}

  Result<T> _result<T>(T value) {
    final failure = nextFailure;
    nextFailure = null;
    return failure == null ? Ok(value) : Err(failure);
  }

  @override
  Future<Result<void>> download(CatalogEntry entry) async {
    calls.add('download:${entry.id}');
    return _result(null);
  }

  @override
  Future<void> pause(String modelId) async => calls.add('pause:$modelId');

  @override
  Future<void> resume(String modelId) async => calls.add('resume:$modelId');

  @override
  Future<void> cancel(String modelId) async => calls.add('cancel:$modelId');

  @override
  Future<Result<InstalledModel?>> importFromDevice() async {
    calls.add('import');
    return _result(null);
  }

  @override
  Future<Result<void>> delete(String modelId) async {
    calls.add('delete:$modelId');
    return _result(null);
  }

  @override
  String pathOf(InstalledModel model) => '/models/${model.fileName}';
}
