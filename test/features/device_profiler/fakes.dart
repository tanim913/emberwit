import 'dart:async';

import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/features/device_profiler/data/benchmark_model_source.dart';
import 'package:emberwit/features/device_profiler/data/device_profile_cache.dart';
import 'package:emberwit/features/device_profiler/data/device_snapshot_source.dart';

class FakeSnapshotSource implements DeviceSnapshotSource {
  new(this.profile, {this.error});

  DeviceProfile profile;
  Error? error;
  int calls = 0;

  @override
  Future<DeviceProfile> snapshot() async {
    calls++;
    if (error != null) throw error!;
    return profile;
  }
}

class MemoryProfileCache implements DeviceProfileCache {
  new([this.saved]);

  DeviceProfile? saved;
  bool failWrites = false;

  @override
  Future<DeviceProfile?> read() async => saved;

  @override
  Future<void> write(DeviceProfile profile) async {
    if (failWrites) throw StateError('disk full');
    saved = profile;
  }
}

class FakeBenchmarkModelSource implements BenchmarkModelSource {
  new([this.result = const Ok(benchmarkFile)]);

  final Result<BenchmarkModelFile> result;

  static const benchmarkFile = BenchmarkModelFile(
    path: '/bench/benchmark.gguf',
    name: 'SmolLM2-135M-Instruct-Q4_0',
    sizeBytes: 91893088,
  );

  @override
  Future<Result<BenchmarkModelFile>> prepare() async => result;
}

/// Repository with scripted results for presentation tests.
class FakeDeviceProfileRepository implements DeviceProfileRepository {
  new({
    this.cached,
    this.refreshed,
    this.refreshFailure,
    this.benchmarkEvents = const [],
  });

  DeviceProfile? cached;
  DeviceProfile? refreshed;
  AppFailure? refreshFailure;
  List<BenchmarkEvent> benchmarkEvents;
  int benchmarkRuns = 0;

  @override
  Future<DeviceProfile?> cachedProfile() async => cached;

  @override
  Future<Result<DeviceProfile>> refreshProfile() async {
    final failure = refreshFailure;
    if (failure != null) return Err(failure);
    return Ok(refreshed ?? cached!);
  }

  @override
  Stream<BenchmarkEvent> runBenchmark() {
    benchmarkRuns++;
    return Stream.fromIterable(benchmarkEvents);
  }
}
