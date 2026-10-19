import 'dart:convert';
import 'dart:io';

import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/features/device_profiler/data/benchmark_runner.dart';
import 'package:emberwit/features/device_profiler/data/device_profile_cache.dart';
import 'package:emberwit/features/device_profiler/data/device_profile_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/device_fixtures.dart';
import '../../../helpers/fake_inference_engine.dart';
import '../fakes.dart';

void main() {
  group('FileDeviceProfileCache', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cache'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes and reads a profile', () async {
      final cache = FileDeviceProfileCache(File('${dir.path}/sub/p.json'));
      expect(await cache.read(), isNull);
      final original = profile(benchmark: benchmarkAt(42));
      await cache.write(original);
      expect(await cache.read(), original);
      expect(File('${dir.path}/sub/p.json.tmp').existsSync(), isFalse);
    });

    test('discards a corrupt file', () async {
      final file = File('${dir.path}/p.json')..writeAsStringSync('{not json');
      expect(await FileDeviceProfileCache(file).read(), isNull);
      expect(file.existsSync(), isFalse);
      file.writeAsStringSync(jsonEncode({'platform': 'android'}));
      expect(await FileDeviceProfileCache(file).read(), isNull);
    });
  });

  group('DeviceProfileRepositoryImpl', () {
    late FakeSnapshotSource snapshots;
    late MemoryProfileCache cache;
    late FakeInferenceEngine engine;

    DeviceProfileRepositoryImpl repository({FakeBenchmarkModelSource? model}) =>
        DeviceProfileRepositoryImpl(
          snapshots: snapshots,
          cache: cache,
          benchmarkModel: model ?? FakeBenchmarkModelSource(),
          runner: BenchmarkRunner(engine: engine),
        );

    setUp(() {
      snapshots = FakeSnapshotSource(profile(totalRamBytes: 6 * gib));
      cache = MemoryProfileCache();
      engine = FakeInferenceEngine(tokens: List.filled(16, 't'));
    });

    test('refresh keeps the cached benchmark and saves', () async {
      cache.saved = profile(benchmark: benchmarkAt(33));
      final result = await repository().refreshProfile();
      final refreshed = result.valueOrNull!;
      expect(refreshed.totalRamBytes, 6 * gib);
      expect(refreshed.benchmark, benchmarkAt(33));
      expect(cache.saved, refreshed);
      expect(await repository().cachedProfile(), refreshed);
    });

    test('refresh reports platform errors', () async {
      snapshots.error = StateError('channel missing');
      final result = await repository().refreshProfile();
      expect(result.failureOrNull, isA<DeviceProfilingFailure>());
    });

    test('a failing cache write does not fail the refresh', () async {
      cache.failWrites = true;
      expect((await repository().refreshProfile()).isOk, isTrue);
    });

    test('benchmark emits progress, then the saved profile', () async {
      final events = await repository().runBenchmark().toList();
      expect(events.first, isA<BenchmarkProgress>());
      expect(
        (events.first as BenchmarkProgress).stage,
        BenchmarkStage.preparing,
      );
      final finished = events.last as BenchmarkFinished;
      expect(finished.profile.benchmark!.generatedTokens, 16);
      expect(cache.saved, finished.profile);
      expect(engine.loadRequests.single.threads, 4);
    });

    test('benchmark fails without the bundled model', () async {
      final events = await repository(
        model: FakeBenchmarkModelSource(
          const Err(BenchmarkUnavailableFailure()),
        ),
      ).runBenchmark().toList();
      expect(
        (events.last as BenchmarkFailed).failure,
        const BenchmarkUnavailableFailure(),
      );
    });

    test('benchmark fails when profiling fails', () async {
      snapshots.error = StateError('x');
      final events = await repository().runBenchmark().toList();
      expect(
        (events.last as BenchmarkFailed).failure,
        isA<DeviceProfilingFailure>(),
      );
    });

    test('benchmark reports engine failures', () async {
      engine = FakeInferenceEngine(
        loadFailure: const ModelLoadFailure(
          ModelLoadFailureReason.insufficientMemory,
        ),
      );
      final events = await repository().runBenchmark().toList();
      expect((events.last as BenchmarkFailed).failure, isA<ModelLoadFailure>());
    });

    test('only one benchmark runs at a time', () async {
      engine = FakeInferenceEngine(
        tokens: List.filled(16, 't'),
        tokenDelay: const Duration(milliseconds: 10),
      );
      final repo = repository();
      final first = repo.runBenchmark().toList();
      final second = await repo.runBenchmark().toList();
      expect(
        (second.single as BenchmarkFailed).failure,
        const EngineBusyFailure(),
      );
      expect((await first).last, isA<BenchmarkFinished>());
      // Free again afterwards.
      expect(
        (await repo.runBenchmark().toList()).last,
        isA<BenchmarkFinished>(),
      );
    });
  });
}
