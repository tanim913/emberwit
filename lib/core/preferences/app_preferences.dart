import 'package:emberwit/core/preferences/preference_keys.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_preferences.freezed.dart';
part 'app_preferences.g.dart';

/// User facing display preferences that the app root needs to build
/// `MaterialApp`: theme and language.
@freezed
abstract class AppPreferencesState with _$AppPreferencesState {
  /// Creates preferences. Defaults follow the operating system.
  const factory({
    @Default(ThemeMode.system) ThemeMode themeMode,

    /// Explicit app language, or `null` to follow the system language.
    Locale? locale,
  }) = _AppPreferencesState;
}

/// Holds the current [AppPreferencesState], saved in shared preferences.
@Riverpod(keepAlive: true)
class AppPreferences extends _$AppPreferences {
  @override
  AppPreferencesState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final theme = prefs.getString(PreferenceKeys.themeMode);
    final language = prefs.getString(PreferenceKeys.locale);
    return AppPreferencesState(
      themeMode: ThemeMode.values.asNameMap()[theme] ?? ThemeMode.system,
      locale: language == null ? null : Locale(language),
    );
  }

  /// Switches between light, dark and system theme.
  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await ref
        .read(sharedPreferencesProvider)
        .setString(PreferenceKeys.themeMode, mode.name);
  }

  /// Sets the app language. `null` follows the system language.
  Future<void> setLocale(Locale? locale) async {
    state = state.copyWith(locale: locale);
    final prefs = ref.read(sharedPreferencesProvider);
    if (locale == null) {
      await prefs.remove(PreferenceKeys.locale);
    } else {
      await prefs.setString(PreferenceKeys.locale, locale.languageCode);
    }
  }
}
