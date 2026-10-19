import 'dart:io';

import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/core/runtime/device_conditions.dart';
import 'package:emberwit/engine/engine_providers.dart';
import 'package:emberwit/features/device_profiler/data/benchmark_model_source.dart';
import 'package:emberwit/features/device_profiler/data/benchmark_runner.dart';
import 'package:emberwit/features/device_profiler/data/device_conditions_source_impl.dart';
import 'package:emberwit/features/device_profiler/data/device_profile_cache.dart';
import 'package:emberwit/features/device_profiler/data/device_profile_repository_impl.dart';
import 'package:emberwit/features/device_profiler/data/device_snapshot_source.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'device_profiler_providers.g.dart';

/// Live device facts.
@Riverpod(keepAlive: true)
DeviceSnapshotSource deviceSnapshotSource(Ref ref) =>
    PlatformDeviceSnapshotSource(clock: ref.watch(clockProvider));

/// The device profiler's [DeviceProfileRepository]. `featureBindings()`
/// exposes it through the shared `deviceProfileRepositoryProvider`.
@Riverpod(keepAlive: true)
DeviceProfileRepository deviceProfilerRepository(Ref ref) {
  final support = ref.watch(appSupportDirectoryProvider);
  return DeviceProfileRepositoryImpl(
    snapshots: ref.watch(deviceSnapshotSourceProvider),
    cache: FileDeviceProfileCache(File('${support.path}/device_profile.json')),
    benchmarkModel: AssetBenchmarkModelSource(
      cacheDirectory: Directory('${support.path}/benchmark'),
    ),
    runner: BenchmarkRunner(
      engine: ref.watch(inferenceEngineProvider),
      clock: ref.watch(clockProvider),
    ),
    logger: ref.watch(appLoggerProvider),
  );
}

/// Live heat, battery and memory readings. `featureBindings()` exposes it as
/// the shared `deviceConditionsSourceProvider`.
@Riverpod(keepAlive: true)
DeviceConditionsSource deviceProfilerConditions(Ref ref) =>
    SnapshotDeviceConditionsSource(ref.watch(deviceSnapshotSourceProvider));
