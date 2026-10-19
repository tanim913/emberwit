import 'package:emberwit/core/preferences/app_preferences.dart';
import 'package:emberwit/core/preferences/general_preferences.dart';
import 'package:emberwit/core/preferences/preference_keys.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/preferences.dart';

ProviderContainer _container(SharedPreferencesWithCache prefs) =>
    ProviderContainer.test(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );

void main() {
  group('AppPreferences', () {
    test('defaults follow the system', () async {
      final container = _container(await inMemoryPreferences());
      final state = container.read(appPreferencesProvider);
      expect(state.themeMode, ThemeMode.system);
      expect(state.locale, isNull);
    });

    test('updates and saves theme mode and locale', () async {
      final prefs = await inMemoryPreferences();
      final container = _container(prefs);
      final notifier = container.read(appPreferencesProvider.notifier);
      await notifier.setThemeMode(ThemeMode.dark);
      await notifier.setLocale(const Locale('bn'));
      expect(
        container.read(appPreferencesProvider),
        const AppPreferencesState(
          themeMode: ThemeMode.dark,
          locale: Locale('bn'),
        ),
      );
      expect(prefs.getString(PreferenceKeys.themeMode), 'dark');
      expect(prefs.getString(PreferenceKeys.locale), 'bn');

      // A new app session reads the saved values.
      final restarted = _container(prefs);
      expect(
        restarted.read(appPreferencesProvider),
        const AppPreferencesState(
          themeMode: ThemeMode.dark,
          locale: Locale('bn'),
        ),
      );

      await notifier.setLocale(null);
      expect(container.read(appPreferencesProvider).locale, isNull);
      expect(prefs.getString(PreferenceKeys.locale), isNull);
    });

    test('ignores an unknown saved theme', () async {
      final container = _container(
        await inMemoryPreferences({PreferenceKeys.themeMode: 'sepia'}),
      );
      expect(
        container.read(appPreferencesProvider).themeMode,
        ThemeMode.system,
      );
    });
  });

  group('general preferences', () {
    test('onboarding starts incomplete and is saved when done', () async {
      final prefs = await inMemoryPreferences();
      final container = _container(prefs);
      expect(container.read(onboardingCompletedProvider), isFalse);
      await container.read(onboardingCompletedProvider.notifier).complete();
      expect(container.read(onboardingCompletedProvider), isTrue);
      expect(_container(prefs).read(onboardingCompletedProvider), isTrue);
    });

    test('default model can be set and cleared', () async {
      final prefs = await inMemoryPreferences();
      final container = _container(prefs);
      expect(container.read(defaultModelIdProvider), isNull);
      await container.read(defaultModelIdProvider.notifier).set('qwen3-q4');
      expect(_container(prefs).read(defaultModelIdProvider), 'qwen3-q4');
      await container.read(defaultModelIdProvider.notifier).set(null);
      expect(_container(prefs).read(defaultModelIdProvider), isNull);
    });

    test('app lock is off by default and saved', () async {
      final prefs = await inMemoryPreferences();
      final container = _container(prefs);
      expect(container.read(appLockEnabledProvider), isFalse);
      await container.read(appLockEnabledProvider.notifier).set(enabled: true);
      expect(_container(prefs).read(appLockEnabledProvider), isTrue);
    });

    test('every key is in the allow list', () {
      expect(
        PreferenceKeys.all,
        containsAll(<String>[
          PreferenceKeys.themeMode,
          PreferenceKeys.locale,
          PreferenceKeys.onboardingCompleted,
          PreferenceKeys.defaultModelId,
          PreferenceKeys.appLock,
          'downloads.wifiOnly',
        ]),
      );
    });
  });
}
