import 'dart:async';

import 'package:emberwit/app/runtime/runtime_supervisor.dart';
import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/runtime/device_conditions.dart';
import 'package:emberwit/core/runtime/runtime_status.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_inference_engine.dart';
import '../../helpers/fake_runtime.dart';

void main() {
  late ProviderContainer container;
  late FakeConditionsSource conditions;
  late FakeInferenceEngine engine;
  late RuntimeSupervisor supervisor;

  RuntimeSupervisor create({
    InferenceEngine? withEngine,
    bool noEngine = false,
    Stream<int>? trimLevels,
  }) {
    final s = RuntimeSupervisor(
      engine: () => noEngine ? null : (withEngine ?? engine),
      conditions: conditions,
      status: container.read(runtimeStatusProvider.notifier),
      trimLevels: trimLevels,
    );
    // Tests dispose started supervisors themselves: timers must be gone
    // before the test ends, and tear-downs run later.
    return s;
  }

  setUp(() {
    container = ProviderContainer.test();
    conditions = FakeConditionsSource();
    engine = FakeInferenceEngine(initialState: EngineState.ready);
  });

  testWidgets('polls conditions while in the foreground', (tester) async {
    supervisor = create()..start();
    await tester.pump();
    expect(conditions.reads, 1);
    conditions.conditions = const DeviceConditions(
      thermalState: ThermalState.serious,
    );
    await tester.pump(const Duration(seconds: 30));
    expect(conditions.reads, 2);
    expect(container.read(runtimeStatusProvider).concerns, {
      RuntimeConcern.warm,
    });
    supervisor.dispose();
  });

  testWidgets('stops a running reply when the phone overheats', (tester) async {
    engine = FakeInferenceEngine(initialState: EngineState.generating);
    conditions.conditions = const DeviceConditions(
      thermalState: ThermalState.critical,
    );
    supervisor = create();
    await supervisor.check();
    expect(engine.cancelled, isTrue);
  });

  testWidgets('keeps a reply running when only slowed down', (tester) async {
    engine = FakeInferenceEngine(initialState: EngineState.generating);
    conditions.conditions = const DeviceConditions(lowPowerMode: true);
    supervisor = create();
    await supervisor.check();
    expect(engine.cancelled, isFalse);
  });

  testWidgets('a failed reading keeps the last advice', (tester) async {
    conditions.error = StateError('channel');
    supervisor = create();
    await supervisor.check();
    expect(container.read(runtimeStatusProvider), RuntimeAdvice.normal);
  });

  testWidgets('a memory warning unloads an idle model', (tester) async {
    supervisor = create()..start();
    await tester.pump();
    tester.binding.handleMemoryPressure();
    await tester.pump();
    // Waits a moment: a reply may be about to start on the loaded model.
    expect(engine.unloadCalls, 0);
    await tester.pump(const Duration(seconds: 5));
    expect(engine.cancelled, isFalse);
    expect(engine.unloadCalls, 1);
    // Silent: no banner, the model reloads with the next message.
    expect(container.read(runtimeStatusProvider), RuntimeAdvice.normal);
    supervisor.dispose();
  });

  testWidgets('a memory warning never cuts a reply short', (tester) async {
    engine = FakeInferenceEngine(initialState: EngineState.generating);
    supervisor = create();
    await supervisor.freeMemory();
    expect(engine.cancelled, isFalse);
    expect(engine.unloadCalls, 0);
    expect(container.read(runtimeStatusProvider), RuntimeAdvice.normal);
    // The reply ends: the model is freed once it stays idle.
    engine.emitState(EngineState.ready);
    await tester.pump(const Duration(seconds: 5));
    expect(engine.unloadCalls, 1);
    supervisor.dispose();
  });

  testWidgets('a reply starting right after loading keeps the model', (
    tester,
  ) async {
    engine = FakeInferenceEngine(initialState: EngineState.loading);
    supervisor = create();
    await supervisor.freeMemory();
    // Loading finishes and the reply starts a moment later.
    engine.emitState(EngineState.ready);
    await tester.pump(const Duration(seconds: 1));
    engine.emitState(EngineState.generating);
    await tester.pump(const Duration(seconds: 10));
    expect(engine.unloadCalls, 0);
    // Only after the reply, and some idle time, is the model freed.
    engine.emitState(EngineState.ready);
    await tester.pump(const Duration(seconds: 5));
    expect(engine.unloadCalls, 1);
    supervisor.dispose();
  });

  testWidgets('returning to the app keeps the model after the reply', (
    tester,
  ) async {
    engine = FakeInferenceEngine(initialState: EngineState.generating);
    // Android sends a memory warning whenever the app leaves the screen.
    supervisor = create()..didChangeAppLifecycleState(AppLifecycleState.hidden);
    await supervisor.freeMemory();
    supervisor.didChangeAppLifecycleState(AppLifecycleState.resumed);
    engine.emitState(EngineState.ready);
    await tester.pump(const Duration(seconds: 10));
    expect(engine.cancelled, isFalse);
    expect(engine.unloadCalls, 0);
    supervisor.dispose();
  });

  testWidgets('Android: leaving the screen is not memory pressure', (
    tester,
  ) async {
    final levels = StreamController<int>.broadcast();
    supervisor = create(trimLevels: levels.stream)..start();
    await tester.pump();
    // What Android sends on hiding the app (UI_HIDDEN, then BACKGROUND),
    // and Flutter's own warning that comes with it.
    levels
      ..add(20)
      ..add(40);
    supervisor.didHaveMemoryPressure();
    await tester.pump(const Duration(seconds: 30));
    expect(engine.unloadCalls, 0);
    // Real pressure frees the idle model.
    levels.add(80);
    await tester.pump(const Duration(seconds: 5));
    expect(engine.unloadCalls, 1);
    supervisor.dispose();
    await levels.close();
  });

  test('which Android levels are memory pressure', () {
    expect([5, 10, 15, 20, 40, 60, 80].where(isMemoryPressure), [15, 60, 80]);
  });

  testWidgets('a memory warning without a model changes nothing', (
    tester,
  ) async {
    supervisor = create(noEngine: true);
    await supervisor.freeMemory();
    supervisor.didHaveMemoryPressure();
    expect(container.read(runtimeStatusProvider), RuntimeAdvice.normal);
  });

  testWidgets('unloads an idle model after a while in the background', (
    tester,
  ) async {
    supervisor = create()..start();
    await tester.pump();
    supervisor.didChangeAppLifecycleState(AppLifecycleState.paused);
    final readsWhenPaused = conditions.reads;
    await tester.pump(const Duration(minutes: 2));
    expect(engine.unloadCalls, 0);
    // No polling in the background.
    expect(conditions.reads, readsWhenPaused);
    await tester.pump(const Duration(minutes: 1));
    expect(engine.unloadCalls, 1);
    supervisor.dispose();
  });

  testWidgets('returning in time keeps the model and resumes polling', (
    tester,
  ) async {
    supervisor = create()..start();
    await tester.pump();
    supervisor.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump(const Duration(minutes: 1));
    supervisor.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(minutes: 5));
    expect(engine.unloadCalls, 0);
    expect(conditions.reads, greaterThan(2));
    supervisor.dispose();
  });

  testWidgets('never unloads in the background while generating', (
    tester,
  ) async {
    engine = FakeInferenceEngine(initialState: EngineState.generating);
    supervisor = create()..start();
    await tester.pump();
    supervisor.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 4));
    expect(engine.unloadCalls, 0);
    supervisor.dispose();
  });
}
