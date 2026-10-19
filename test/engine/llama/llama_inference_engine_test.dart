import 'dart:async';

import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:emberwit/engine/llama/llama_inference_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llama_ffi/llama_ffi.dart';

import '../fakes/fake_llama_runtime.dart';

const _load = LoadModelRequest(path: '/models/fake.gguf');
const _prompt = GenerationRequest(prompt: RawPrompt('Once upon a time'));

Future<LlamaInferenceEngine> _loadedEngine({
  LlamaRuntimeFactory factory = fastRuntime,
}) async {
  final engine = LlamaInferenceEngine(runtimeFactory: factory);
  final last = await engine.loadModel(_load).last;
  expect(last, isA<ModelLoaded>());
  return engine;
}

typedef LlamaRuntimeFactory = LlamaRuntime Function();

void main() {
  group('LlamaInferenceEngine', () {
    test('starts idle and loads a model in the worker isolate', () async {
      final engine = LlamaInferenceEngine(
        runtimeFactory: fastRuntime,
        processorCount: 8,
        useMetal: false,
      );
      addTearDown(engine.dispose);
      expect(engine.state, EngineState.idle);
      final states = <EngineState>[];
      final sub = engine.stateChanges.listen(states.add);
      addTearDown(sub.cancel);

      final events = await engine.loadModel(_load).toList();
      expect(events.whereType<ModelLoadProgress>(), isNotEmpty);
      final loaded = events.last as ModelLoaded;
      expect(loaded.info.threads, 4);
      expect(loaded.info.gpuLayers, 0);
      expect(engine.state, EngineState.ready);
      expect(states, [EngineState.loading, EngineState.ready]);

      final stats = await engine.getStats();
      expect(stats.model?.path, '/models/fake.gguf');
      expect(stats.loadDuration, isNotNull);
    });

    test('offloads every layer on Metal by default', () async {
      final engine = LlamaInferenceEngine(
        runtimeFactory: fastRuntime,
        useMetal: true,
      );
      addTearDown(engine.dispose);
      final loaded = await engine.loadModel(_load).last as ModelLoaded;
      expect(loaded.info.gpuLayers, 999);
    });

    test('streams generated tokens and records stats', () async {
      final engine = await _loadedEngine();
      addTearDown(engine.dispose);
      final events = await engine.generate(_prompt).toList();
      final text = events.whereType<TokenGenerated>().map((e) => e.text).join();
      expect(text, '1 2 3 4 5 6 7 8 9 10 ');
      final done = events.last as GenerationCompleted;
      expect(done.stats.generatedTokens, 10);
      expect(done.stats.stopReason, StopReason.endOfSequence);
      expect(engine.state, EngineState.ready);
      expect((await engine.getStats()).lastGeneration, same(done.stats));
    });

    test('fails generation without a model', () async {
      final engine = LlamaInferenceEngine(runtimeFactory: fastRuntime);
      addTearDown(engine.dispose);
      final events = await engine.generate(_prompt).toList();
      expect(
        (events.single as GenerationFailed).failure,
        const NoModelLoadedFailure(),
      );
    });

    test('rejects concurrent work while generating', () async {
      final engine = await _loadedEngine(factory: slowRuntime);
      addTearDown(engine.dispose);
      final first = engine.generate(_prompt).toList();
      final second = await engine.generate(_prompt).toList();
      expect(
        (second.single as GenerationFailed).failure,
        const EngineBusyFailure(),
      );
      final load = await engine.loadModel(_load).toList();
      expect(
        (load.single as ModelLoadFailed).failure,
        const EngineBusyFailure(),
      );
      await engine.cancel();
      await first;
    });

    test('cancel stops a running generation', () async {
      final engine = await _loadedEngine(factory: slowRuntime);
      addTearDown(engine.dispose);
      final events = <GenerationEvent>[];
      final done = Completer<void>();
      engine.generate(_prompt).listen(events.add, onDone: done.complete);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await engine.cancel();
      await done.future;
      final stats = (events.last as GenerationCompleted).stats;
      expect(stats.stopReason, StopReason.cancelled);
      expect(stats.generatedTokens, lessThan(500));
      expect(engine.state, EngineState.ready);
    });

    test('cancelling the subscription cancels generation', () async {
      final engine = await _loadedEngine(factory: slowRuntime);
      addTearDown(engine.dispose);
      final sub = engine.generate(_prompt).listen(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      // The engine becomes ready again once the worker stops.
      await engine.stateChanges.firstWhere((s) => s == EngineState.ready);
      final stats = (await engine.getStats()).lastGeneration!;
      expect(stats.stopReason, StopReason.cancelled);
    });

    test('unload frees the model and interrupts running work', () async {
      final engine = await _loadedEngine(factory: slowRuntime);
      addTearDown(engine.dispose);
      final generation = engine.generate(_prompt).toList();
      expect(await engine.unloadModel(), const Ok<void>(null));
      final events = await generation;
      expect(
        (events.last as GenerationCompleted).stats.stopReason,
        StopReason.cancelled,
      );
      expect(engine.state, EngineState.idle);
      expect((await engine.getStats()).model, isNull);
    });

    test('unload without a worker succeeds', () async {
      final engine = LlamaInferenceEngine(runtimeFactory: fastRuntime);
      addTearDown(engine.dispose);
      expect(await engine.unloadModel(), const Ok<void>(null));
    });

    test('a failed load leaves the engine idle', () async {
      final engine = LlamaInferenceEngine(runtimeFactory: failingLoadRuntime);
      addTearDown(engine.dispose);
      final last = await engine.loadModel(_load).last;
      expect(
        (last as ModelLoadFailed).failure,
        const ModelLoadFailure(ModelLoadFailureReason.invalidFormat),
      );
      expect(engine.state, EngineState.idle);
    });

    test('recovers after the worker isolate dies', () async {
      final engine = await _loadedEngine(factory: crashingRuntime);
      addTearDown(engine.dispose);
      final events = await engine.generate(_prompt).toList();
      expect(
        (events.last as GenerationFailed).failure,
        isA<UnexpectedFailure>(),
      );
      expect(engine.state, EngineState.idle);
      // A new worker is started on the next request.
      expect(await engine.loadModel(_load).last, isA<ModelLoaded>());
    });

    test('refuses work after dispose', () async {
      final engine = await _loadedEngine();
      await engine.dispose();
      await engine.dispose();
      expect(
        (await engine.generate(_prompt).single as GenerationFailed).failure,
        isA<UnexpectedFailure>(),
      );
      expect(await engine.loadModel(_load).single, isA<ModelLoadFailed>());
      expect(await engine.unloadModel(), isA<Err<void>>());
    });
  });

  test('defaultThreadCount stays between 1 and 4', () {
    expect(defaultThreadCount(1), 1);
    expect(defaultThreadCount(3), 3);
    expect(defaultThreadCount(8), 4);
  });
}
