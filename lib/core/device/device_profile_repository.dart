import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'device_profile_repository.g.dart';

/// Source of the device profile, shared by onboarding, the model catalog and
/// settings. Implemented by the device_profiler feature and wired in
/// `lib/app/providers/feature_bindings.dart`.
abstract interface class DeviceProfileRepository {
  /// The last saved profile, or `null` before the first profiling. Fast: no
  /// platform calls.
  Future<DeviceProfile?> cachedProfile();

  /// Reads current values from the device (RAM, storage, thermal, battery),
  /// keeps the last benchmark, saves and returns the profile.
  Future<Result<DeviceProfile>> refreshProfile();

  /// Runs the micro benchmark (about 10 seconds) and saves the result into
  /// the profile. Emits progress, then exactly one [BenchmarkFinished] or
  /// [BenchmarkFailed].
  Stream<BenchmarkEvent> runBenchmark();
}

/// Progress of [DeviceProfileRepository.runBenchmark].
@immutable
sealed class BenchmarkEvent {
  const new();
}

/// The benchmark moved to [stage]; [fraction] is overall progress 0 to 1.
final class BenchmarkProgress extends BenchmarkEvent {
  /// Creates the event.
  const new(this.stage, this.fraction);

  /// Current step.
  final BenchmarkStage stage;

  /// Overall progress, 0 to 1.
  final double fraction;
}

/// Steps of a benchmark run.
enum BenchmarkStage {
  /// Unpacking the bundled benchmark model.
  preparing,

  /// Loading the model into the engine.
  loading,

  /// Generating tokens.
  running,
}

/// The benchmark finished and [profile] contains its result.
final class BenchmarkFinished extends BenchmarkEvent {
  /// Creates the event.
  const new(this.profile);

  /// The updated profile.
  final DeviceProfile profile;
}

/// The benchmark failed.
final class BenchmarkFailed extends BenchmarkEvent {
  /// Creates the event.
  const new(this.failure);

  /// What went wrong.
  final AppFailure failure;
}

/// The device profile repository. Overridden with the real implementation
/// in `featureBindings()`; reading it without an override is a programming
/// error.
@Riverpod(keepAlive: true)
DeviceProfileRepository deviceProfileRepository(Ref ref) => throw StateError(
  'deviceProfileRepositoryProvider must be overridden by featureBindings().',
);
