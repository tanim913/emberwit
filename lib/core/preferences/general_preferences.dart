import 'package:emberwit/core/preferences/preference_keys.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'general_preferences.g.dart';

/// Whether onboarding is done. The router shows onboarding until it is.
@Riverpod(keepAlive: true)
class OnboardingCompleted extends _$OnboardingCompleted {
  @override
  bool build() =>
      ref
          .watch(sharedPreferencesProvider)
          .getBool(PreferenceKeys.onboardingCompleted) ??
      false;

  /// Marks onboarding as done (finished or skipped).
  Future<void> complete() async {
    state = true;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(PreferenceKeys.onboardingCompleted, true);
  }
}

/// Model new conversations start with; `null` uses the newest installed
/// model.
@Riverpod(keepAlive: true)
class DefaultModelId extends _$DefaultModelId {
  @override
  String? build() => ref
      .watch(sharedPreferencesProvider)
      .getString(PreferenceKeys.defaultModelId);

  /// Changes the default. `null` returns to the newest installed model.
  Future<void> set(String? modelId) async {
    state = modelId;
    final prefs = ref.read(sharedPreferencesProvider);
    if (modelId == null) {
      await prefs.remove(PreferenceKeys.defaultModelId);
    } else {
      await prefs.setString(PreferenceKeys.defaultModelId, modelId);
    }
  }
}

/// Whether the app asks for the device's biometrics or screen lock when it
/// opens.
@Riverpod(keepAlive: true)
class AppLockEnabled extends _$AppLockEnabled {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(PreferenceKeys.appLock) ??
      false;

  /// Turns the lock on or off. Callers authenticate the user first.
  Future<void> set({required bool enabled}) async {
    state = enabled;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(PreferenceKeys.appLock, enabled);
  }
}
