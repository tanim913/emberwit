import 'dart:async';

import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/device/device_tier_classifier.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'device_check_controller.freezed.dart';
part 'device_check_controller.g.dart';

/// State of the device check screen.
@freezed
abstract class DeviceCheckState with _$DeviceCheckState {
  /// Creates the state.
  const factory({
    /// Latest profile, cached or fresh.
    DeviceProfile? profile,

    /// Tier of [profile].
    DeviceTier? tier,

    /// Reading device values.
    @Default(false) bool refreshing,

    /// Current benchmark step while the benchmark runs.
    BenchmarkStage? benchmarkStage,

    /// Benchmark progress 0 to 1 while it runs.
    double? benchmarkProgress,

    /// Last error.
    AppFailure? failure,
  }) = _DeviceCheckState;

  const new _();

  /// Whether the benchmark is running.
  bool get benchmarking => benchmarkStage != null;
}

/// Loads the device profile and runs the benchmark for the device check
/// screen (and, later, onboarding and settings).
@riverpod
class DeviceCheckController extends _$DeviceCheckController {
  static const _classifier = DeviceTierClassifier();
  StreamSubscription<BenchmarkEvent>? _benchmark;

  DeviceProfileRepository get _repository =>
      ref.read(deviceProfileRepositoryProvider);

  @override
  DeviceCheckState build() {
    ref.onDispose(() => unawaited(_benchmark?.cancel()));
    unawaited(_initialLoad());
    return const DeviceCheckState(refreshing: true);
  }

  Future<void> _initialLoad() async {
    final cached = await _repository.cachedProfile();
    if (!ref.mounted) return;
    if (cached != null) state = _withProfile(state, cached);
    await refresh();
  }

  /// Re-reads live device values, keeping the last benchmark.
  Future<void> refresh() async {
    state = state.copyWith(refreshing: true, failure: null);
    final result = await _repository.refreshProfile();
    if (!ref.mounted) return;
    state = switch (result) {
      Ok(:final value) => _withProfile(
        state,
        value,
      ).copyWith(refreshing: false),
      Err(:final failure) => state.copyWith(
        refreshing: false,
        failure: failure,
      ),
    };
  }

  /// Runs (or reruns) the micro benchmark.
  void runBenchmark() {
    if (state.benchmarking) return;
    state = state.copyWith(
      benchmarkStage: BenchmarkStage.preparing,
      benchmarkProgress: 0,
      failure: null,
    );
    _benchmark = _repository.runBenchmark().listen((event) {
      state = switch (event) {
        BenchmarkProgress(:final stage, :final fraction) => state.copyWith(
          benchmarkStage: stage,
          benchmarkProgress: fraction,
        ),
        BenchmarkFinished(:final profile) => _withProfile(
          state,
          profile,
        ).copyWith(benchmarkStage: null, benchmarkProgress: null),
        BenchmarkFailed(:final failure) => state.copyWith(
          benchmarkStage: null,
          benchmarkProgress: null,
          failure: failure,
        ),
      };
    });
  }

  static DeviceCheckState _withProfile(
    DeviceCheckState state,
    DeviceProfile profile,
  ) => state.copyWith(profile: profile, tier: _classifier.classify(profile));
}
