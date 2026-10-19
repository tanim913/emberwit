import 'package:emberwit/core/preferences/download_preferences.dart';

/// Keys of every value kept in shared preferences.
///
/// Preferences hold small, non-sensitive settings only. Chats live in the
/// encrypted database and keys in the platform keystore.
abstract final class PreferenceKeys {
  /// Theme mode name (`system`, `light`, `dark`).
  static const String themeMode = 'display.themeMode';

  /// App language code, absent to follow the system.
  static const String locale = 'display.locale';

  /// Whether the user finished (or skipped) onboarding.
  static const String onboardingCompleted = 'app.onboardingCompleted';

  /// Model new conversations use, absent for the newest installed one.
  static const String defaultModelId = 'chat.defaultModelId';

  /// Language voice typing last listened for (`english`, `bengali`),
  /// absent to follow the app language.
  static const String voiceLanguage = 'chat.voiceLanguage';

  /// Whether the app lock is on.
  static const String appLock = 'security.appLock';

  /// Every key, for the preferences allow list in `bootstrap`.
  static const Set<String> all = {
    themeMode,
    locale,
    onboardingCompleted,
    defaultModelId,
    voiceLanguage,
    appLock,
    ...DownloadPreferenceKeys.all,
  };
}
