import 'package:emberwit/core/preferences/preference_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Preferences backed by memory, as bootstrap would create them, starting
/// with [values].
Future<SharedPreferencesWithCache> inMemoryPreferences([
  Map<String, Object> values = const {},
]) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData({...values});
  return await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(
      allowList: PreferenceKeys.all,
    ),
  );
}

/// Preferences of a user who finished onboarding.
Future<SharedPreferencesWithCache> onboardedPreferences([
  Map<String, Object> values = const {},
]) =>
    inMemoryPreferences({PreferenceKeys.onboardingCompleted: true, ...values});
