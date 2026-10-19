import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/logging/app_logger.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:emberwit/engine/llama/cancel_flag.dart';
import 'package:emberwit/engine/llama/llama_protocol.dart';
import 'package:emberwit/engine/llama/llama_worker.dart';
import 'package:flutter/foundation.dart';
import 'package:llama_ffi/llama_ffi.dart';

/// Creates the production llama.cpp runtime inside the worker isolate.
LlamaRuntime createFfiLlamaRuntime() => FfiLlamaRuntime();

/// Default CPU thread count for [cores] logical cores.
///
/// Phones have at most four fast cores, and running on slow efficiency cores
/// makes every thread wait for the slowest one, so more than four threads
/// rarely helps. The device profiler refines this per device.
int defaultThreadCount(int cores) => cores.clamp(1, 4);

/// [InferenceEngine] backed by llama.cpp running in a long lived background
/// isolate.
///
/// The UI isolate only sends small typed messages ([WorkerCommand]) and
/// receives events ([WorkerEvent]); all native work happens in the worker.
/// The worker starts on first use, so app startup does not pay for it. If
/// the worker dies, pending requests fail and the next request starts a new
/// worker.
final class LlamaInferenceEngine implements InferenceEngine {
  /// Creates the engine.
  ///
  /// [_runtimeFactory] runs inside the worker; tests pass a fake runtime.
  /// [processorCount] and [useMetal] override platform detection for tests.
  new({
    this._runtimeFactory = createFfiLlamaRuntime,
    this._logger = const SilentAppLogger(),
    int? processorCount,
    bool? useMetal,
  }) : _processorCount = processorCount ?? Platform.numberOfProcessors,
       _useMetal = useMetal ?? (Platform.isIOS || Platform.isMacOS);

  final LlamaRuntime Function() _runtimeFactory;
  final AppLogger _logger;
  final int _processorCount;
  final bool _useMetal;

  final NativeCancelFlag _cancelFlag = NativeCancelFlag.allocate();
  final StreamController<EngineState> _states =
      StreamController<EngineState>.broadcast();
  final Map<int, _PendingRequest> _pending = {};

  EngineState _state = EngineState.idle;
  Future<_WorkerConnection>? _worker;
  int _nextId = 0;
  bool _disposed = false;
  ModelInfo? _model;
  Duration? _loadDuration;
  GenerationStats? _lastGeneration;

  @override
  EngineState get state => _state;

  @override
  Stream<EngineState> get stateChanges => _states.stream;

  void _setState(EngineState next) {
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  bool get _busy =>
      _state == EngineState.loading || _state == EngineState.generating;

  @override
  Stream<ModelLoadEvent> loadModel(LoadModelRequest request) {
    final controller = StreamController<ModelLoadEvent>();
    if (_disposed || _busy) {
      return _failedStream(
        controller,
        ModelLoadFailed(
          _disposed ? const UnexpectedFailure() : const EngineBusyFailure(),
        ),
      );
    }
    _cancelFlag.clear();
    _model = null;
    _setState(EngineState.loading);
    final id = _nextId++;
    _pending[id] = _LoadRequest(controller);
    unawaited(
      _send(
        id,
        LoadCommand(
          id,
          request: request,
          threads: request.threads ?? defaultThreadCount(_processorCount),
          gpuLayers: request.gpuLayers ?? (_useMetal ? 999 : 0),
        ),
      ),
    );
    return controller.stream;
  }

  @override
  Stream<GenerationEvent> generate(GenerationRequest request) {
    late final StreamController<GenerationEvent> controller;
    controller = StreamController<GenerationEvent>(
      onCancel: () {
        if (_pending.values.any((p) => p.owns(controller))) unawaited(cancel());
      },
    );
    if (_disposed || _busy) {
      return _failedStream(
        controller,
        GenerationFailed(
          _disposed ? const UnexpectedFailure() : const EngineBusyFailure(),
        ),
      );
    }
    if (_model == null) {
      return _failedStream(
        controller,
        const GenerationFailed(NoModelLoadedFailure()),
      );
    }
    _cancelFlag.clear();
    _setState(EngineState.generating);
    final id = _nextId++;
    _pending[id] = _GenerateRequest(controller);
    unawaited(_send(id, GenerateCommand(id, request)));
    return controller.stream;
  }

  @override
  Future<void> cancel() async {
    if (_busy) _cancelFlag.set();
  }

  @override
  Future<Result<void>> unloadModel() async {
    if (_disposed) return const Err(UnexpectedFailure());
    if (_worker == null) return const Ok(null);
    // Stop running work; the worker handles commands in order, so the
    // unload runs right after the cancelled operation finishes.
    if (_busy) _cancelFlag.set();
    final completer = Completer<Result<void>>();
    final id = _nextId++;
    _pending[id] = _AckRequest(completer);
    await _send(id, UnloadCommand(id));
    return await completer.future;
  }

  @override
  Future<Result<int>> countTokens(String text) async {
    if (_disposed) return const Err(UnexpectedFailure());
    if (_model == null || _worker == null) {
      return const Err(NoModelLoadedFailure());
    }
    final completer = Completer<Result<int>>();
    final id = _nextId++;
    _pending[id] = _CountRequest(completer);
    await _send(id, CountTokensCommand(id, text));
    return await completer.future;
  }

  @override
  Future<EngineStats> getStats() async => EngineStats(
    state: _state,
    model: _model,
    loadDuration: _loadDuration,
    lastGeneration: _lastGeneration,
  );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelFlag.set();
    final worker = _worker;
    if (worker != null) {
      try {
        final connection = await worker;
        final exited = connection.exited.first;
        connection.commands.send(ShutdownCommand(_nextId++));
        await exited.timeout(
          const Duration(seconds: 3),
          onTimeout: connection.isolate.kill,
        );
      } on Object catch (error) {
        _logger.warning('Engine worker did not start cleanly: $error');
      }
    }
    _failAllPending(const UnexpectedFailure());
    _worker = null;
    _model = null;
    _setState(EngineState.idle);
    await _states.close();
    _cancelFlag.free();
  }

  Future<void> _send(int id, WorkerCommand command) async {
    try {
      final connection = await (_worker ??= _spawnWorker());
      connection.commands.send(command);
    } on Object catch (error, stackTrace) {
      _logger.error('Engine worker failed to start', error, stackTrace);
      _worker = null;
      _complete(
        id,
        FailedEvent(
          id,
          ModelLoadFailure(
            ModelLoadFailureReason.engineUnavailable,
            cause: error.toString(),
          ),
        ),
      );
    }
  }

  Future<_WorkerConnection> _spawnWorker() async {
    final events = ReceivePort('llama-engine-events');
    final exits = ReceivePort('llama-engine-exit');
    final errors = ReceivePort('llama-engine-errors');
    final ready = Completer<SendPort>();
    events.listen((message) {
      if (message is WorkerReady) {
        ready.complete(message.commands);
      } else if (message is CommandEvent) {
        _complete(message.id, message);
      }
    });
    errors.listen((error) => _logger.error('Engine worker error', error));
    final exited = exits.asBroadcastStream();
    final isolate = await Isolate.spawn(
      llamaWorkerMain,
      WorkerBootstrap(
        events: events.sendPort,
        runtimeFactory: _runtimeFactory,
        cancelFlagAddress: _cancelFlag.address,
      ),
      onExit: exits.sendPort,
      onError: errors.sendPort,
      debugName: 'llama-engine',
    );
    unawaited(
      exited.first.then((_) {
        events.close();
        errors.close();
        exits.close();
        _onWorkerExit();
      }),
    );
    final commands = await ready.future.timeout(const Duration(seconds: 15));
    _logger.info('Engine worker started');
    return _WorkerConnection(isolate, commands, exited);
  }

  void _onWorkerExit() {
    if (_disposed) return;
    _logger.warning('Engine worker exited');
    _worker = null;
    _model = null;
    _failAllPending(const UnexpectedFailure());
    _setState(EngineState.idle);
  }

  void _failAllPending(AppFailure failure) {
    for (final id in _pending.keys.toList()) {
      _complete(id, FailedEvent(id, failure));
    }
  }

  void _complete(int id, CommandEvent event) {
    final request = _pending[id];
    if (request == null) return;
    switch ((request, event)) {
      case (
        _LoadRequest(:final controller),
        LoadProgressEvent(:final fraction),
      ):
        controller.add(ModelLoadProgress(fraction));
      case (
        _LoadRequest(:final controller),
        LoadedEvent(:final info, :final duration),
      ):
        _pending.remove(id);
        _model = info;
        _loadDuration = duration;
        _setState(EngineState.ready);
        controller.add(ModelLoaded(info, duration));
        unawaited(controller.close());
      case (_LoadRequest(:final controller), FailedEvent(:final failure)):
        _pending.remove(id);
        _model = null;
        _setState(EngineState.idle);
        controller.add(ModelLoadFailed(failure));
        unawaited(controller.close());
      case (_GenerateRequest(:final controller), TokenEvent(:final text)):
        controller.add(TokenGenerated(text));
      case (
        _GenerateRequest(:final controller),
        GenerationDoneEvent(:final stats),
      ):
        _pending.remove(id);
        _lastGeneration = stats;
        _setState(_model == null ? EngineState.idle : EngineState.ready);
        controller.add(GenerationCompleted(stats));
        unawaited(controller.close());
      case (_GenerateRequest(:final controller), FailedEvent(:final failure)):
        _pending.remove(id);
        if (failure is NoModelLoadedFailure) _model = null;
        _setState(_model == null ? EngineState.idle : EngineState.ready);
        controller.add(GenerationFailed(failure));
        unawaited(controller.close());
      case (_CountRequest(:final completer), TokenCountEvent(:final count)):
        _pending.remove(id);
        completer.complete(Ok(count));
      case (_CountRequest(:final completer), FailedEvent(:final failure)):
        _pending.remove(id);
        completer.complete(Err(failure));
      case (_AckRequest(:final completer), DoneEvent()):
        _pending.remove(id);
        _model = null;
        if (!_busy) _setState(EngineState.idle);
        completer.complete(const Ok(null));
      case (_AckRequest(:final completer), FailedEvent(:final failure)):
        _pending.remove(id);
        completer.complete(Err(failure));
      case _:
        _logger.warning('Unexpected ${event.runtimeType} for request $id');
    }
  }

  static Stream<T> _failedStream<T>(StreamController<T> controller, T event) {
    controller.add(event);
    unawaited(controller.close());
    return controller.stream;
  }
}

@immutable
final class _WorkerConnection {
  const new(this.isolate, this.commands, this.exited);

  final Isolate isolate;
  final SendPort commands;
  final Stream<Object?> exited;
}

sealed class _PendingRequest {
  const new();

  bool owns(StreamController<Object?> controller) => false;
}

final class _LoadRequest extends _PendingRequest {
  const new(this.controller);

  final StreamController<ModelLoadEvent> controller;
}

final class _GenerateRequest extends _PendingRequest {
  const new(this.controller);

  final StreamController<GenerationEvent> controller;

  @override
  bool owns(StreamController<Object?> other) => identical(other, controller);
}

final class _CountRequest extends _PendingRequest {
  const new(this.completer);

  final Completer<Result<int>> completer;
}

final class _AckRequest extends _PendingRequest {
  const new(this.completer);

  final Completer<Result<void>> completer;
}
