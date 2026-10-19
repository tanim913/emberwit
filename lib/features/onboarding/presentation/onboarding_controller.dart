import 'dart:async';

import 'package:emberwit/core/catalog/catalog_repository.dart';
import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/device/device_tier_classifier.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/preferences/general_preferences.dart';
import 'package:emberwit/core/recommendation/recommendation_engine.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'onboarding_controller.freezed.dart';
part 'onboarding_controller.g.dart';

/// What onboarding knows about the device and the model to start with.
@freezed
abstract class OnboardingState with _$OnboardingState {
  /// Creates the state.
  const factory({
    /// Device profile, `null` while profiling or when it failed.
    DeviceProfile? profile,

    /// Performance class of the device.
    DeviceTier? tier,

    /// Reading device facts.
    @Default(true) bool profiling,

    /// The best model for this device, `null` when none fits.
    CatalogEntry? suggested,

    /// Recommendation for [suggested].
    ModelRecommendation? recommendation,

    /// Whether a model is already on the phone (onboarding was reset, or a
    /// download started earlier).
    @Default(false) bool hasModel,

    /// The suggested model's download started.
    @Default(false) bool downloadStarted,

    /// Why the last action failed.
    AppFailure? failure,
  }) = _OnboardingState;
}

/// Drives onboarding: profiles the device, suggests a first model, starts
/// its download and marks onboarding done.
@riverpod
class OnboardingController extends _$OnboardingController {
  @override
  OnboardingState build() {
    unawaited(_load());
    return const OnboardingState();
  }

  Future<void> _load() async {
    final profiles = ref.read(deviceProfileRepositoryProvider);
    final library = ref.read(modelLibraryProvider);
    final profile =
        await profiles.cachedProfile() ??
        (await profiles.refreshProfile()).valueOrNull;
    final snapshot = await ref.read(catalogRepositoryProvider).current();
    await library.initialize();
    if (!ref.mounted) return;
    final installed = library.state.installed;
    CatalogEntry? suggested;
    ModelRecommendation? recommendation;
    if (profile != null) {
      final candidates = [
        for (final entry in snapshot.catalog.models)
          // A first model should not need a license agreement.
          if (!entry.license.requiresAgreement) entry,
      ];
      final ranked = const RecommendationEngine().recommendAll(
        candidates.map((e) => e.toSpec()),
        profile,
      );
      for (final r in ranked) {
        if (r.label == RecommendationLabel.notSupported) continue;
        recommendation = r;
        suggested = snapshot.catalog.entry(r.modelId);
        break;
      }
    }
    state = state.copyWith(
      profile: profile,
      tier: profile == null
          ? null
          : const DeviceTierClassifier().classify(profile),
      profiling: false,
      suggested: suggested,
      recommendation: recommendation,
      hasModel: installed.isNotEmpty || library.state.downloads.isNotEmpty,
    );
  }

  /// Starts downloading the suggested model.
  Future<void> downloadSuggested() async {
    final entry = state.suggested;
    if (entry == null || state.downloadStarted) return;
    state = state.copyWith(failure: null);
    final result = await ref.read(modelLibraryProvider).download(entry);
    if (!ref.mounted) return;
    state = switch (result) {
      Ok() => state.copyWith(downloadStarted: true),
      Err(:final failure) => state.copyWith(failure: failure),
    };
  }

  /// Marks onboarding as done.
  Future<void> finish() =>
      ref.read(onboardingCompletedProvider.notifier).complete();
}
