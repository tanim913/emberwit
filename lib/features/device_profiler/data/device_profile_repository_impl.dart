import 'dart:async';

import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/logging/app_logger.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/features/device_profiler/data/benchmark_model_source.dart';
import 'package:emberwit/features/device_profiler/data/benchmark_runner.dart';
import 'package:emberwit/features/device_profiler/data/device_profile_cache.dart';
import 'package:emberwit/features/device_profiler/data/device_snapshot_source.dart';

/// [DeviceProfileRepository] combining a live snapshot, the cached benchmark
/// and the benchmark runner.
final class DeviceProfileRepositoryImpl implements DeviceProfileRepository {
  /// Creates the repository.
  new({
    required this._snapshots,
    required this._cache,
    required this._benchmarkModel,
    required this._runner,
    this._logger = const SilentAppLogger(),
  });

  final DeviceSnapshotSource _snapshots;
  final DeviceProfileCache _cache;
  final BenchmarkModelSource _benchmarkModel;
  final BenchmarkRunner _runner;
  final AppLogger _logger;
  bool _benchmarkRunning = false;

  @override
  Future<DeviceProfile?> cachedProfile() => _cache.read();

  @override
  Future<Result<DeviceProfile>> refreshProfile() async {
    final DeviceProfile snapshot;
    try {
      snapshot = await _snapshots.snapshot();
    } on Object catch (error, stackTrace) {
      _logger.error('Device snapshot failed', error, stackTrace);
      return Err(
        DeviceProfilingFailure(
          'snapshot failed',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
    final cached = await _cache.read();
    final profile = snapshot.copyWith(benchmark: cached?.benchmark);
    await _save(profile);
    return Ok(profile);
  }

  @override
  Stream<BenchmarkEvent> runBenchmark() {
    final controller = StreamController<BenchmarkEvent>();
    if (_benchmarkRunning) {
      controller.add(const BenchmarkFailed(EngineBusyFailure()));
      unawaited(controller.close());
      return controller.stream;
    }
    _benchmarkRunning = true;
    unawaited(
      _benchmark(controller).whenComplete(() {
        _benchmarkRunning = false;
        unawaited(controller.close());
      }),
    );
    return controller.stream;
  }

  Future<void> _benchmark(StreamController<BenchmarkEvent> out) async {
    out.add(const BenchmarkProgress(BenchmarkStage.preparing, 0));
    final refreshed = await refreshProfile();
    final DeviceProfile profile;
    switch (refreshed) {
      case Ok(:final value):
        profile = value;
      case Err(:final failure):
        out.add(BenchmarkFailed(failure));
        return;
    }
    final model = await _benchmarkModel.prepare();
    final BenchmarkModelFile file;
    switch (model) {
      case Ok(:final value):
        file = value;
      case Err(:final failure):
        out.add(BenchmarkFailed(failure));
        return;
    }
    final result = await _runner.run(
      file,
      threads: profile.recommendedThreads,
      onProgress: (stage, fraction) =>
          out.add(BenchmarkProgress(stage, fraction)),
    );
    switch (result) {
      case Ok(:final value):
        final updated = profile.copyWith(benchmark: value);
        await _save(updated);
        _logger.info(
          'Benchmark: ${value.tokensPerSecond.toStringAsFixed(1)} tok/s',
        );
        out.add(BenchmarkFinished(updated));
      case Err(:final failure):
        out.add(BenchmarkFailed(failure));
    }
  }

  Future<void> _save(DeviceProfile profile) async {
    try {
      await _cache.write(profile);
    } on Object catch (error, stackTrace) {
      // A failed cache write only costs a re-profile next time.
      _logger.warning('Device profile cache write failed: $error $stackTrace');
    }
  }
}
