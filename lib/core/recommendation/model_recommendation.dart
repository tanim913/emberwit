import 'package:flutter/foundation.dart';

/// Verdict for one model on one device.
enum RecommendationLabel {
  /// Fits in memory and runs at a comfortable speed.
  recommended,

  /// Fits, but replies will be slow.
  runsSlowly,

  /// Cannot run on this device, or not usefully.
  notSupported,
}

/// Why a model got its label. Presentation turns reasons into localized
/// sentences (`describeRecommendationReason`).
@immutable
sealed class RecommendationReason {
  const new();

  /// Whether this reason alone makes the model
  /// [RecommendationLabel.notSupported].
  bool get isBlocking => false;
}

/// Estimated speed is comfortable.
final class RunsWell extends RecommendationReason {
  /// Creates the reason.
  const new(this.tokensPerSecond);

  /// Estimated generation speed.
  final double tokensPerSecond;

  @override
  bool operator ==(Object other) =>
      other is RunsWell && other.tokensPerSecond == tokensPerSecond;

  @override
  int get hashCode => Object.hash(RunsWell, tokensPerSecond);
}

/// Estimated speed is usable but slow.
final class SlowSpeed extends RecommendationReason {
  /// Creates the reason.
  const new(this.tokensPerSecond);

  /// Estimated generation speed.
  final double tokensPerSecond;

  @override
  bool operator ==(Object other) =>
      other is SlowSpeed && other.tokensPerSecond == tokensPerSecond;

  @override
  int get hashCode => Object.hash(SlowSpeed, tokensPerSecond);
}

/// Estimated speed is too slow to be useful.
final class TooSlow extends RecommendationReason {
  /// Creates the reason.
  const new(this.tokensPerSecond);

  /// Estimated generation speed.
  final double tokensPerSecond;

  @override
  bool get isBlocking => true;

  @override
  bool operator ==(Object other) =>
      other is TooSlow && other.tokensPerSecond == tokensPerSecond;

  @override
  int get hashCode => Object.hash(TooSlow, tokensPerSecond);
}

/// The model and its context need more memory than the app may use.
final class NotEnoughMemory extends RecommendationReason {
  /// Creates the reason.
  const new({required this.requiredBytes, required this.budgetBytes});

  /// Memory the model needs at the smallest usable context.
  final int requiredBytes;

  /// Memory the app may use for a model on this device.
  final int budgetBytes;

  @override
  bool get isBlocking => true;

  @override
  bool operator ==(Object other) =>
      other is NotEnoughMemory &&
      other.requiredBytes == requiredBytes &&
      other.budgetBytes == budgetBytes;

  @override
  int get hashCode => Object.hash(NotEnoughMemory, requiredBytes, budgetBytes);
}

/// The device has less RAM than the catalog's minimum for this model.
final class BelowMinimumRam extends RecommendationReason {
  /// Creates the reason.
  const new({required this.minimumBytes, required this.totalBytes});

  /// Catalog minimum.
  final int minimumBytes;

  /// Device RAM.
  final int totalBytes;

  @override
  bool get isBlocking => true;

  @override
  bool operator ==(Object other) =>
      other is BelowMinimumRam &&
      other.minimumBytes == minimumBytes &&
      other.totalBytes == totalBytes;

  @override
  int get hashCode => Object.hash(BelowMinimumRam, minimumBytes, totalBytes);
}

/// Not enough free storage to download the model safely.
final class NotEnoughStorage extends RecommendationReason {
  /// Creates the reason.
  const new({required this.requiredBytes, required this.freeBytes});

  /// Model size plus the safety buffer.
  final int requiredBytes;

  /// Free space now.
  final int freeBytes;

  @override
  bool get isBlocking => true;

  @override
  bool operator ==(Object other) =>
      other is NotEnoughStorage &&
      other.requiredBytes == requiredBytes &&
      other.freeBytes == freeBytes;

  @override
  int get hashCode => Object.hash(NotEnoughStorage, requiredBytes, freeBytes);
}

/// The context had to be shortened for the model to fit in memory.
final class ContextReduced extends RecommendationReason {
  /// Creates the reason.
  const new({required this.from, required this.to});

  /// Context the tier would normally use.
  final int from;

  /// Context that fits.
  final int to;

  @override
  bool operator ==(Object other) =>
      other is ContextReduced && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(ContextReduced, from, to);
}

/// No benchmark has run, so speed is estimated from the device tier.
final class SpeedEstimatedWithoutBenchmark extends RecommendationReason {
  /// Creates the reason.
  const new();

  @override
  bool operator ==(Object other) => other is SpeedEstimatedWithoutBenchmark;

  @override
  int get hashCode => (SpeedEstimatedWithoutBenchmark).hashCode;
}

/// The recommendation for one model.
@immutable
final class ModelRecommendation {
  /// Creates a recommendation.
  const new({
    required this.modelId,
    required this.label,
    required this.reasons,
    required this.contextLength,
    required this.estimatedTokensPerSecond,
    required this.requiredMemoryBytes,
  });

  /// Catalog id of the model.
  final String modelId;

  /// The verdict.
  final RecommendationLabel label;

  /// Why, most important first.
  final List<RecommendationReason> reasons;

  /// Context length to use with this model on this device.
  final int contextLength;

  /// Estimated generation speed in tokens per second.
  final double estimatedTokensPerSecond;

  /// Memory needed at [contextLength]: weights, KV cache and overhead.
  final int requiredMemoryBytes;
}
