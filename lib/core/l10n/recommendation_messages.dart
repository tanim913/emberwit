import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/recommendation/model_recommendation.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';

/// Bytes as decimal gigabytes, the unit phones show for RAM and storage.
double gigabytes(int bytes) => bytes / 1e9;

/// Localized name of a recommendation [label].
String recommendationLabelText(
  AppLocalizations l10n,
  RecommendationLabel label,
) => switch (label) {
  RecommendationLabel.recommended => l10n.recommendationRecommended,
  RecommendationLabel.runsSlowly => l10n.recommendationRunsSlowly,
  RecommendationLabel.notSupported => l10n.recommendationNotSupported,
};

/// Localized sentence explaining [reason].
String describeRecommendationReason(
  AppLocalizations l10n,
  RecommendationReason reason,
) => switch (reason) {
  RunsWell(:final tokensPerSecond) => l10n.reasonRunsWell(tokensPerSecond),
  SlowSpeed(:final tokensPerSecond) => l10n.reasonSlowSpeed(tokensPerSecond),
  TooSlow(:final tokensPerSecond) => l10n.reasonTooSlow(tokensPerSecond),
  NotEnoughMemory(:final requiredBytes, :final budgetBytes) =>
    l10n.reasonNotEnoughMemory(
      gigabytes(requiredBytes),
      gigabytes(budgetBytes),
    ),
  BelowMinimumRam(:final minimumBytes, :final totalBytes) =>
    l10n.reasonBelowMinimumRam(gigabytes(minimumBytes), gigabytes(totalBytes)),
  NotEnoughStorage(:final requiredBytes, :final freeBytes) =>
    l10n.reasonNotEnoughStorage(gigabytes(requiredBytes), gigabytes(freeBytes)),
  ContextReduced(:final from, :final to) => l10n.reasonContextReduced(from, to),
  SpeedEstimatedWithoutBenchmark() => l10n.reasonSpeedEstimated,
};

/// Localized name of a device [tier].
String deviceTierName(AppLocalizations l10n, DeviceTier tier) => switch (tier) {
  DeviceTier.low => l10n.deviceTierLow,
  DeviceTier.mid => l10n.deviceTierMid,
  DeviceTier.high => l10n.deviceTierHigh,
  DeviceTier.flagship => l10n.deviceTierFlagship,
};

/// Localized explanation of what a device [tier] can run.
String deviceTierDescription(AppLocalizations l10n, DeviceTier tier) =>
    switch (tier) {
      DeviceTier.low => l10n.deviceTierLowDescription,
      DeviceTier.mid => l10n.deviceTierMidDescription,
      DeviceTier.high => l10n.deviceTierHighDescription,
      DeviceTier.flagship => l10n.deviceTierFlagshipDescription,
    };

/// Localized name of a thermal [state].
String thermalStateName(AppLocalizations l10n, ThermalState state) =>
    switch (state) {
      ThermalState.nominal => l10n.thermalNominal,
      ThermalState.fair => l10n.thermalFair,
      ThermalState.serious => l10n.thermalSerious,
      ThermalState.critical => l10n.thermalCritical,
      ThermalState.unknown => l10n.thermalUnknown,
    };
