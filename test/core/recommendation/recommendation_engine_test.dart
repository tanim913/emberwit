import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/recommendation/recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/device_fixtures.dart';

const engine = RecommendationEngine();

ModelSpec spec({
  int fileSizeBytes = 500 * mib,
  int parameterCount = 600000000,
  int kv = 100 * 1024,
  int context = 4096,
  int minRam = 0,
  bool installed = false,
}) => ModelSpec(
  id: 'm',
  parameterCount: parameterCount,
  fileSizeBytes: fileSizeBytes,
  kvCacheBytesPerToken: kv,
  recommendedContextLength: context,
  minRamBytes: minRam,
  isInstalled: installed,
);

void main() {
  group('memory rule', () {
    test('uses 45% of RAM on Android and 50% on iOS', () {
      // 1.9 GiB of weights + KV + overhead against 4 GiB of RAM:
      // 45% = 1.8 GiB (too small), 50% = 2 GiB (fits at 1024 context).
      final model = spec(fileSizeBytes: 1800 * mib, kv: 32 * 1024);
      final android = engine.recommend(
        model,
        profile(totalRamBytes: 4 * gib, benchmark: benchmarkAt(200)),
      );
      final ios = engine.recommend(
        model,
        profile(
          platform: DevicePlatform.ios,
          totalRamBytes: 4 * gib,
          benchmark: benchmarkAt(200),
        ),
      );
      expect(android.label, RecommendationLabel.notSupported);
      expect(android.reasons.first, isA<NotEnoughMemory>());
      expect(ios.label, isNot(RecommendationLabel.notSupported));
    });

    test('counts weights, KV cache for the context and overhead', () {
      final model = spec(kv: 1000);
      expect(
        engine.requiredMemory(model, 2048),
        500 * mib + 1000 * 2048 + 64 * mib,
      );
    });

    test('halves the context until the model fits', () {
      // 8 GiB RAM -> high tier -> 4096 context. Budget: 3.6 GiB.
      // 3 GiB weights + 256 KiB/token: 4096 -> 4 GiB (no), 2048 -> 3.5 GiB.
      final model = spec(fileSizeBytes: 3 * gib, kv: 256 * 1024);
      final r = engine.recommend(model, profile(benchmark: benchmarkAt(2000)));
      expect(r.contextLength, 2048);
      expect(r.reasons, contains(const ContextReduced(from: 4096, to: 2048)));
      expect(r.label, isNot(RecommendationLabel.notSupported));
    });

    test('reports the need at the minimum context when nothing fits', () {
      final model = spec(fileSizeBytes: 5 * gib);
      final r = engine.recommend(model, profile(benchmark: benchmarkAt(2000)));
      expect(r.contextLength, 1024);
      final reason = r.reasons.whereType<NotEnoughMemory>().single;
      expect(reason.requiredBytes, engine.requiredMemory(model, 1024));
      expect(reason.budgetBytes, (8 * gib * 0.45).floor());
    });

    test("never exceeds the model's recommended context", () {
      final r = engine.recommend(
        spec(context: 2048),
        profile(totalRamBytes: 16 * gib, benchmark: benchmarkAt(300)),
      );
      expect(r.contextLength, 2048);
      expect(r.reasons.whereType<ContextReduced>(), isEmpty);
    });

    test('respects the catalog minimum RAM', () {
      final r = engine.recommend(
        spec(minRam: 6 * gib),
        profile(totalRamBytes: 4 * gib, benchmark: benchmarkAt(300)),
      );
      expect(r.label, RecommendationLabel.notSupported);
      expect(
        r.reasons,
        contains(
          const BelowMinimumRam(minimumBytes: 6 * gib, totalBytes: 4 * gib),
        ),
      );
    });
  });

  group('storage rule', () {
    test('needs the file size plus 1 GB free', () {
      final model = spec();
      final tight = engine.recommend(
        model,
        profile(
          freeStorageBytes: 500 * mib + gib - 1,
          benchmark: benchmarkAt(300),
        ),
      );
      expect(tight.label, RecommendationLabel.notSupported);
      expect(
        tight.reasons,
        contains(
          const NotEnoughStorage(
            requiredBytes: 500 * mib + gib,
            freeBytes: 500 * mib + gib - 1,
          ),
        ),
      );
      final enough = engine.recommend(
        model,
        profile(freeStorageBytes: 500 * mib + gib, benchmark: benchmarkAt(300)),
      );
      expect(enough.reasons.whereType<NotEnoughStorage>(), isEmpty);
    });

    test('does not apply to installed models', () {
      final r = engine.recommend(
        spec(installed: true),
        profile(freeStorageBytes: 0, benchmark: benchmarkAt(300)),
      );
      expect(r.label, RecommendationLabel.recommended);
    });
  });

  group('speed rule', () {
    test('estimates speed from benchmark bandwidth and model size', () {
      final model = spec(fileSizeBytes: 1000 * mib);
      final bench = benchmarkAt(100);
      final r = engine.recommend(model, profile(benchmark: bench));
      expect(
        r.estimatedTokensPerSecond,
        closeTo(0.85 * bench.effectiveBandwidth / (1000 * mib), 1e-9),
      );
    });

    double benchFor(double targetTps, int size) =>
        targetTps * size / 0.85 / 91893088;

    test('labels by estimated speed', () {
      final model = spec(fileSizeBytes: 1000 * mib);
      RecommendationLabel labelAt(double tps) => engine
          .recommend(
            model,
            profile(benchmark: benchmarkAt(benchFor(tps, 1000 * mib))),
          )
          .label;

      expect(labelAt(8), RecommendationLabel.recommended);
      expect(labelAt(7.9), RecommendationLabel.runsSlowly);
      expect(labelAt(2), RecommendationLabel.runsSlowly);
      expect(labelAt(1.9), RecommendationLabel.notSupported);
    });

    test('gives the matching reason', () {
      final model = spec(fileSizeBytes: 1000 * mib);
      final fast = engine.recommend(
        model,
        profile(benchmark: benchmarkAt(benchFor(20, 1000 * mib))),
      );
      expect(fast.reasons.first, isA<RunsWell>());
      final slow = engine.recommend(
        model,
        profile(benchmark: benchmarkAt(benchFor(4, 1000 * mib))),
      );
      expect(slow.reasons.first, isA<SlowSpeed>());
      final tooSlow = engine.recommend(
        model,
        profile(benchmark: benchmarkAt(benchFor(1, 1000 * mib))),
      );
      expect(tooSlow.reasons.first, isA<TooSlow>());
      expect(tooSlow.reasons.first.isBlocking, isTrue);
    });

    test('falls back to the tier estimate without a benchmark', () {
      final r = engine.recommend(spec(), profile(totalRamBytes: 12 * gib));
      expect(r.reasons, contains(const SpeedEstimatedWithoutBenchmark()));
      expect(
        r.estimatedTokensPerSecond,
        closeTo(0.85 * 35e9 / (500 * mib), 1e-6),
      );
    });

    test('handles a zero size model without dividing by zero', () {
      expect(
        engine.estimateTokensPerSecond(spec(fileSizeBytes: 0), 1000000000),
        0,
      );
    });
  });

  test('lists blocking reasons first', () {
    final r = engine.recommend(
      spec(fileSizeBytes: 5 * gib),
      profile(freeStorageBytes: gib, benchmark: benchmarkAt(1)),
    );
    expect(r.reasons.take(3).every((reason) => reason.isBlocking), isTrue);
    expect(r.reasons.whereType<TooSlow>(), hasLength(1));
  });

  test('recommendAll sorts best first', () {
    final results = engine.recommendAll(
      seedModels,
      profile(totalRamBytes: (5.6 * gib).round(), benchmark: benchmarkAt(60)),
    );
    final labels = results.map((r) => r.label.index).toList();
    expect(labels, [...labels]..sort());
    final recommended = results
        .where((r) => r.label == RecommendationLabel.recommended)
        .toList();
    expect(recommended, isNotEmpty);
    final slow = results
        .where((r) => r.label == RecommendationLabel.runsSlowly)
        .map((r) => r.estimatedTokensPerSecond)
        .toList();
    expect(slow, [...slow]..sort((a, b) => b.compareTo(a)));
  });

  test('recommendAll orders recommended models largest first', () {
    final results = engine.recommendAll([
      qwen3Small,
      gemma3Small,
      qwen3Medium,
    ], profile(totalRamBytes: 16 * gib, benchmark: benchmarkAt(1000)));
    expect(results.map((r) => r.modelId), [
      'qwen3-1.7b',
      'gemma3-1b',
      'qwen3-0.6b',
    ]);
  });

  test('reasons and recommendations compare by value', () {
    expect(const RunsWell(1), const RunsWell(1));
    expect(const SlowSpeed(1).hashCode, const SlowSpeed(1).hashCode);
    expect(const TooSlow(1), const TooSlow(1));
    expect(
      const NotEnoughMemory(requiredBytes: 1, budgetBytes: 2).hashCode,
      const NotEnoughMemory(requiredBytes: 1, budgetBytes: 2).hashCode,
    );
    expect(
      const BelowMinimumRam(minimumBytes: 1, totalBytes: 2).hashCode,
      const BelowMinimumRam(minimumBytes: 1, totalBytes: 2).hashCode,
    );
    expect(
      const NotEnoughStorage(requiredBytes: 1, freeBytes: 2).hashCode,
      const NotEnoughStorage(requiredBytes: 1, freeBytes: 2).hashCode,
    );
    expect(
      const ContextReduced(from: 2, to: 1).hashCode,
      const ContextReduced(from: 2, to: 1).hashCode,
    );
    expect(
      const SpeedEstimatedWithoutBenchmark().hashCode,
      const SpeedEstimatedWithoutBenchmark().hashCode,
    );
    expect(const RunsWell(1), isNot(const SlowSpeed(1)));
  });

  group('kvCacheBytesPerToken', () {
    test('uses the catalog value when present', () {
      expect(kvCacheBytesPerToken(qwen3Large), 147456);
    });

    test('falls back by parameter count', () {
      int fallback(int params) => kvCacheBytesPerToken(
        ModelSpec(id: 'x', parameterCount: params, fileSizeBytes: 1),
      );
      expect(fallback(600000000), 112 * 1024);
      expect(fallback(3000000000), 160 * 1024);
      expect(fallback(8000000000), 256 * 1024);
      expect(fallback(14000000000), 384 * 1024);
    });
  });

  test('platform memory fractions', () {
    const config = RecommendationConfig();
    expect(config.memoryFraction(DevicePlatform.android), 0.45);
    expect(config.memoryFraction(DevicePlatform.ios), 0.50);
    expect(config.memoryFraction(DevicePlatform.other), 0.45);
  });
}
