import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/device/device_tier_classifier.dart';
import 'package:emberwit/core/recommendation/model_recommendation.dart';
import 'package:emberwit/core/recommendation/model_spec.dart';

export 'package:emberwit/core/recommendation/model_recommendation.dart';
export 'package:emberwit/core/recommendation/model_spec.dart';

const int _mib = 1024 * 1024;
const int _gib = 1024 * _mib;

/// Tunable thresholds of the [RecommendationEngine].
final class RecommendationConfig {
  /// Creates a configuration. Defaults follow the product requirements.
  const new({
    this.androidMemoryFraction = 0.45,
    this.iosMemoryFraction = 0.50,
    this.otherMemoryFraction = 0.45,
    this.computeOverheadBytes = 64 * _mib,
    this.storageBufferBytes = _gib,
    this.recommendedMinTokensPerSecond = 8,
    this.usableMinTokensPerSecond = 2,
    this.minimumContextLength = 1024,
    this.bandwidthEfficiency = 0.85,
    this.fallbackBandwidth = const {
      DeviceTier.low: 4e9,
      DeviceTier.mid: 10e9,
      DeviceTier.high: 20e9,
      DeviceTier.flagship: 35e9,
    },
  });

  /// Share of total RAM a model may use on Android.
  final double androidMemoryFraction;

  /// Share of total RAM a model may use on iOS. Assumes the increased memory
  /// limit entitlement (`com.apple.developer.kernel.increased-memory-limit`).
  final double iosMemoryFraction;

  /// Share of total RAM on other platforms.
  final double otherMemoryFraction;

  /// Compute buffers and runtime overhead on top of weights and KV cache.
  final int computeOverheadBytes;

  /// Free storage that must remain after downloading a model.
  final int storageBufferBytes;

  /// Estimated speed at or above which a model is recommended.
  final double recommendedMinTokensPerSecond;

  /// Estimated speed below which a model is not supported.
  final double usableMinTokensPerSecond;

  /// Shortest context worth offering.
  final int minimumContextLength;

  /// Share of measured bandwidth a larger model achieves. Larger models are
  /// purely memory bound, while the small benchmark model also pays fixed
  /// per-token costs, so the ratio is not exactly 1.
  final double bandwidthEfficiency;

  /// Assumed weight bandwidth (bytes/s) per tier when no benchmark ran.
  final Map<DeviceTier, double> fallbackBandwidth;

  /// Memory fraction for [platform].
  double memoryFraction(DevicePlatform platform) => switch (platform) {
    DevicePlatform.android => androidMemoryFraction,
    DevicePlatform.ios => iosMemoryFraction,
    DevicePlatform.other => otherMemoryFraction,
  };
}

/// Decides which models a device can run well.
///
/// Pure Dart, no I/O: give it a [DeviceProfile] and [ModelSpec]s. Three rules:
///
/// 1. **Memory**: weights + KV cache for the context + overhead must fit in a
///    share of total RAM (45% Android, 50% iOS). If the tier's default
///    context does not fit, the context is halved down to
///    [RecommendationConfig.minimumContextLength].
/// 2. **Storage**: free space must exceed the file size plus 1 GB, unless the
///    model is already installed.
/// 3. **Speed**: generation is memory bandwidth bound, so the benchmark's
///    effective bandwidth divided by the model size estimates tokens per
///    second.
final class RecommendationEngine {
  /// Creates an engine.
  const new({
    this.config = const RecommendationConfig(),
    this.classifier = const DeviceTierClassifier(),
  });

  /// Thresholds.
  final RecommendationConfig config;

  /// Tier classifier.
  final DeviceTierClassifier classifier;

  /// Recommendation for one [model] on the device described by [profile].
  ModelRecommendation recommend(ModelSpec model, DeviceProfile profile) {
    final tier = classifier.classify(profile);
    final blocking = <RecommendationReason>[];
    final info = <RecommendationReason>[];

    if (model.minRamBytes > 0 && profile.totalRamBytes < model.minRamBytes) {
      blocking.add(
        BelowMinimumRam(
          minimumBytes: model.minRamBytes,
          totalBytes: profile.totalRamBytes,
        ),
      );
    }

    // Memory rule, trying shorter contexts before giving up.
    final budget =
        (profile.totalRamBytes * config.memoryFraction(profile.platform))
            .floor();
    final preferred = _min(
      defaultContextLength(tier),
      model.recommendedContextLength,
    );
    var context = preferred;
    while (context > config.minimumContextLength &&
        requiredMemory(model, context) > budget) {
      context = _max(context ~/ 2, config.minimumContextLength);
    }
    final needed = requiredMemory(model, context);
    if (needed > budget) {
      blocking.add(NotEnoughMemory(requiredBytes: needed, budgetBytes: budget));
    } else if (context < preferred) {
      info.add(ContextReduced(from: preferred, to: context));
    }

    // Storage rule.
    if (!model.isInstalled) {
      final requiredStorage = model.fileSizeBytes + config.storageBufferBytes;
      if (profile.freeStorageBytes < requiredStorage) {
        blocking.add(
          NotEnoughStorage(
            requiredBytes: requiredStorage,
            freeBytes: profile.freeStorageBytes,
          ),
        );
      }
    }

    // Speed rule.
    final benchmark = profile.benchmark;
    final bandwidth =
        benchmark?.effectiveBandwidth ?? config.fallbackBandwidth[tier]!;
    if (benchmark == null) info.add(const SpeedEstimatedWithoutBenchmark());
    final speed = estimateTokensPerSecond(model, bandwidth);
    final RecommendationReason speedReason;
    if (speed >= config.recommendedMinTokensPerSecond) {
      speedReason = RunsWell(speed);
    } else if (speed >= config.usableMinTokensPerSecond) {
      speedReason = SlowSpeed(speed);
    } else {
      speedReason = TooSlow(speed);
      blocking.add(speedReason);
    }

    final label = blocking.isNotEmpty
        ? RecommendationLabel.notSupported
        : speedReason is SlowSpeed
        ? RecommendationLabel.runsSlowly
        : RecommendationLabel.recommended;

    return ModelRecommendation(
      modelId: model.id,
      label: label,
      reasons: [...blocking, if (speedReason is! TooSlow) speedReason, ...info],
      contextLength: context,
      estimatedTokensPerSecond: speed,
      requiredMemoryBytes: needed,
    );
  }

  /// Recommendations for all [models], best first: recommended models
  /// (largest first, as larger models answer better), then slow ones
  /// (fastest first), then unsupported ones.
  List<ModelRecommendation> recommendAll(
    Iterable<ModelSpec> models,
    DeviceProfile profile,
  ) {
    final specs = {for (final m in models) m.id: m};
    return [for (final m in specs.values) recommend(m, profile)]..sort((a, b) {
      final byLabel = a.label.index.compareTo(b.label.index);
      if (byLabel != 0) return byLabel;
      if (a.label == RecommendationLabel.recommended) {
        return specs[b.modelId]!.parameterCount.compareTo(
          specs[a.modelId]!.parameterCount,
        );
      }
      return b.estimatedTokensPerSecond.compareTo(a.estimatedTokensPerSecond);
    });
  }

  /// Memory needed to run [model] with [contextLength] tokens of context.
  int requiredMemory(ModelSpec model, int contextLength) =>
      model.fileSizeBytes +
      kvCacheBytesPerToken(model) * contextLength +
      config.computeOverheadBytes;

  /// Estimated tokens per second for [model] at [bandwidth] bytes/s.
  double estimateTokensPerSecond(ModelSpec model, double bandwidth) {
    if (model.fileSizeBytes <= 0) return 0;
    return config.bandwidthEfficiency * bandwidth / model.fileSizeBytes;
  }
}

int _min(int a, int b) => a < b ? a : b;
int _max(int a, int b) => a > b ? a : b;
