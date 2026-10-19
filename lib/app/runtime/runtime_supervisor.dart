import 'dart:async';

import 'package:emberwit/core/logging/app_logger.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/core/runtime/device_conditions.dart';
import 'package:emberwit/core/runtime/runtime_status.dart';
import 'package:emberwit/engine/engine_providers.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'runtime_supervisor.g.dart';

/// Keeps the model within the device's limits while the app runs.
///
/// * **Memory**: on real memory pressure an idle model is unloaded; it
///   reloads on the next message. On Android that is an `onTrimMemory` level
///   from `trimLevels` that [isMemoryPressure] accepts: Flutter's own
///   warning also fires when the app is merely hidden (and Android sends
///   "background" seconds later), which would unload the model at every app
///   switch. iOS `didReceiveMemoryWarning` is always real. A reply in
///   progress (or a model still loading) is never cut short; the model is
///   unloaded once the reply ends, unless the app came back to the
///   foreground in the meantime.
/// * **Heat and battery**: while the app is in the foreground, conditions are
///   read every [pollInterval] and fed to [RuntimeStatus]. A critical state
///   stops the reply in progress; the chat refuses or slows down new ones.
/// * **Background**: after [backgroundUnloadDelay] in the background with no
///   reply running, the model is unloaded so the OS does not kill the app
///   for its memory.
final class RuntimeSupervisor with WidgetsBindingObserver {
  /// Creates the supervisor. `engine` returns `null` when no engine has been
  /// created yet (nothing to free).
  new({
    required this._engine,
    required this._conditions,
    required this._status,
    this._logger = const SilentAppLogger(),
    this.pollInterval = const Duration(seconds: 30),
    this.backgroundUnloadDelay = const Duration(minutes: 3),
    this.memoryIdleDelay = const Duration(seconds: 5),
    this._trimLevels,
  });

  final InferenceEngine? Function() _engine;
  final DeviceConditionsSource _conditions;
  final RuntimeStatus _status;
  final AppLogger _logger;
  final Stream<int>? _trimLevels;
  StreamSubscription<int>? _trims;

  /// How often conditions are read in the foreground.
  final Duration pollInterval;

  /// How long the app may sit in the background before the model is freed.
  final Duration backgroundUnloadDelay;

  /// How long the model must stay idle after a memory warning before it is
  /// freed. A model is briefly idle between finishing loading and starting
  /// the reply; freeing it in that gap would fail the reply.
  final Duration memoryIdleDelay;

  Timer? _poll;
  Timer? _unload;
  StreamSubscription<EngineState>? _idleWatch;
  Timer? _memoryUnload;
  bool _started = false;

  /// Starts observing the app and polling conditions.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _trims = _trimLevels?.listen((level) {
      if (isMemoryPressure(level)) unawaited(freeMemory());
    });
    _startPolling();
  }

  /// Stops everything.
  void dispose() {
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
    unawaited(_trims?.cancel());
    _trims = null;
    _poll?.cancel();
    _unload?.cancel();
    unawaited(_idleWatch?.cancel());
    _memoryUnload?.cancel();
  }

  void _startPolling() {
    _poll?.cancel();
    unawaited(check());
    _poll = Timer.periodic(pollInterval, (_) => unawaited(check()));
  }

  /// Reads conditions once and applies the resulting advice.
  @visibleForTesting
  Future<void> check() async {
    try {
      _status.updateConditions(await _conditions.read());
    } on Object catch (e) {
      _logger.warning('Reading device conditions failed: ${e.runtimeType}');
      _status.refresh();
    }
    final engine = _engine();
    if (engine != null &&
        !_status.advice.canGenerate &&
        engine.state == EngineState.generating) {
      _logger.info('Stopping generation: ${_status.advice.primary?.name}');
      await engine.cancel();
    }
  }

  @override
  void didHaveMemoryPressure() {
    // With Android's own levels, Flutter's warning adds nothing but the
    // false alarm on hiding.
    if (_trimLevels == null) unawaited(freeMemory());
  }

  /// Frees the model once it has been idle for [memoryIdleDelay], waiting
  /// for any reply or load in progress to finish first.
  @visibleForTesting
  Future<void> freeMemory() async {
    final engine = _engine();
    if (engine == null || engine.state == EngineState.idle) return;
    _scheduleMemoryUnload(engine);
  }

  void _scheduleMemoryUnload(InferenceEngine engine) {
    unawaited(_idleWatch?.cancel());
    _idleWatch = null;
    _memoryUnload?.cancel();
    if (engine.state == EngineState.ready) {
      _memoryUnload = Timer(memoryIdleDelay, () {
        _memoryUnload = null;
        switch (engine.state) {
          case EngineState.ready:
            // Silent: the model reloads on the next message.
            _logger.info('Memory pressure: unloading the idle model');
            unawaited(engine.unloadModel());
          case EngineState.loading || EngineState.generating:
            // A reply started meanwhile: try again once it ends.
            _scheduleMemoryUnload(engine);
          case EngineState.idle:
            break;
        }
      });
      return;
    }
    if (engine.state == EngineState.idle) return;
    _idleWatch = engine.stateChanges.listen((state) {
      if (state == EngineState.ready) _scheduleMemoryUnload(engine);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _poll?.cancel();
        _poll = null;
        _unload ??= Timer(backgroundUnloadDelay, _unloadIfIdle);
      case AppLifecycleState.resumed:
        _unload?.cancel();
        _unload = null;
        // Back on screen: the warning that came with leaving no longer
        // applies to the reply the user is now watching.
        unawaited(_idleWatch?.cancel());
        _idleWatch = null;
        _memoryUnload?.cancel();
        _memoryUnload = null;
        if (_started && _poll == null) _startPolling();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  void _unloadIfIdle() {
    _unload = null;
    final engine = _engine();
    if (engine == null || engine.state != EngineState.ready) return;
    _logger.info('In the background: unloading the model');
    unawaited(engine.unloadModel());
  }
}

/// Whether Android `onTrimMemory` [level] means memory is really short:
/// `TRIM_MEMORY_RUNNING_CRITICAL` (15) while visible, `MODERATE` (60) or
/// `COMPLETE` (80) in the background, or `onLowMemory` (sent as 80).
/// `UI_HIDDEN` (20) and `BACKGROUND` (40) only say the app left the screen.
bool isMemoryPressure(int level) => level == 15 || level >= 60;

/// Android `onTrimMemory` levels from `MainActivity`, or `null` on other
/// platforms.
Stream<int>? _androidTrimLevels(Ref ref) {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  const channel = MethodChannel('app.emberwit/memory');
  final levels = StreamController<int>.broadcast();
  channel.setMethodCallHandler((call) async {
    if (call.method == 'trimMemory' && call.arguments is int) {
      levels.add(call.arguments as int);
    }
  });
  ref.onDispose(() {
    channel.setMethodCallHandler(null);
    unawaited(levels.close());
  });
  return levels.stream;
}

/// The running supervisor. Started by the app root.
@Riverpod(keepAlive: true)
RuntimeSupervisor runtimeSupervisor(Ref ref) {
  final supervisor = RuntimeSupervisor(
    engine: () => ref.exists(inferenceEngineProvider)
        ? ref.read(inferenceEngineProvider)
        : null,
    conditions: ref.watch(deviceConditionsSourceProvider),
    status: ref.read(runtimeStatusProvider.notifier),
    logger: ref.watch(appLoggerProvider),
    trimLevels: _androidTrimLevels(ref),
  )..start();
  ref.onDispose(supervisor.dispose);
  return supervisor;
}
