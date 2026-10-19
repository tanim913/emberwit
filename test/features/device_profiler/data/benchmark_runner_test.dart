import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/core/utils/clock.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:emberwit/features/device_profiler/data/benchmark_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_inference_engine.dart';
import '../fakes.dart';

void main() {
  final clock = FixedClock(DateTime.utc(2026, 9, 24, 12));
  const model = FakeBenchmarkModelSource.benchmarkFile;

  Future<(Result<BenchmarkResult>, List<(BenchmarkStage, double)>)> run(
    FakeInferenceEngine engine, {
    Duration budget = const Duration(seconds: 10),
    int maxTokens = 128,
  }) async {
    final progress = <(BenchmarkStage, double)>[];
    final result = await BenchmarkRunner(
      engine: engine,
      clock: clock,
      timeBudget: budget,
      maxTokens: maxTokens,
    ).run(model, threads: 3, onProgress: (s, f) => progress.add((s, f)));
    return (result, progress);
  }

  test('measures speed with the benchmark model and unloads it', () async {
    final engine = FakeInferenceEngine(tokens: List.filled(20, 'x'));
    final (result, progress) = await run(engine);
    final bench = (result as Ok<BenchmarkResult>).value;
    expect(bench.modelName, model.name);
    expect(bench.modelSizeBytes, model.sizeBytes);
    expect(bench.generatedTokens, 20);
    expect(bench.tokensPerSecond, greaterThan(0));
    expect(bench.loadTimeMs, 120);
    expect(bench.threads, 4);
    expect(bench.measuredAt, clock.now());

    final request = engine.loadRequests.single;
    expect(request.path, model.path);
    expect(request.threads, 3);
    expect(request.contextLength, 512);
    expect(engine.unloadCalls, 1);
    expect(engine.requests.single.prompt, const RawPrompt(benchmarkPrompt));
    expect(engine.requests.single.sampling.temperature, 0);

    expect(progress.first.$1, BenchmarkStage.loading);
    expect(progress.last, (BenchmarkStage.running, 1.0));
    final fractions = progress.map((p) => p.$2).toList();
    expect(fractions, [...fractions]..sort());
  });

  test('stops at the time budget', () async {
    final engine = FakeInferenceEngine(
      tokens: List.filled(1000, 'x'),
      tokenDelay: const Duration(milliseconds: 5),
    );
    final watch = Stopwatch()..start();
    final (result, _) = await run(
      engine,
      budget: const Duration(milliseconds: 300),
      maxTokens: 1000,
    );
    expect(result.isOk, isTrue);
    // The budget has a floor of three seconds for the generation phase.
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(engine.cancelled, isTrue);
    expect(engine.unloadCalls, 1);
  });

  test('fails when the model does not load, and still unloads', () async {
    final engine = FakeInferenceEngine(
      loadFailure: const ModelLoadFailure(
        ModelLoadFailureReason.insufficientMemory,
      ),
    );
    final (result, _) = await run(engine);
    expect(
      result.failureOrNull,
      const ModelLoadFailure(ModelLoadFailureReason.insufficientMemory),
    );
    expect(engine.unloadCalls, 1);
  });

  test('fails when generation fails', () async {
    final engine = FakeInferenceEngine(
      generationFailure: const GenerationFailure('decode failed'),
    );
    final (result, _) = await run(engine);
    expect(result.failureOrNull, const GenerationFailure('decode failed'));
  });

  test('rejects too short runs', () async {
    final engine = FakeInferenceEngine(tokens: const ['a', 'b']);
    final (result, _) = await run(engine);
    expect(result.failureOrNull, isA<GenerationFailure>());
  });

  test('refuses to run while the engine is busy', () async {
    final engine = FakeInferenceEngine(initialState: EngineState.generating);
    final (result, _) = await run(engine);
    expect(result.failureOrNull, const EngineBusyFailure());
    expect(engine.loadRequests, isEmpty);
  });
}
