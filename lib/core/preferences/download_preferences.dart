import 'package:emberwit/core/providers/core_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'download_preferences.g.dart';

/// Preference keys owned by download settings.
abstract final class DownloadPreferenceKeys {
  /// Whether model downloads wait for Wi-Fi.
  static const String wifiOnly = 'downloads.wifiOnly';

  /// Every key, for the preferences allow list.
  static const Set<String> all = {wifiOnly};
}

/// Whether model downloads use Wi-Fi only. On by default: models are
/// hundreds of megabytes to gigabytes, often too much for mobile data.
@Riverpod(keepAlive: true)
class WifiOnlyDownloads extends _$WifiOnlyDownloads {
  @override
  bool build() =>
      ref
          .watch(sharedPreferencesProvider)
          .getBool(DownloadPreferenceKeys.wifiOnly) ??
      true;

  /// Changes the preference. Applies to downloads started afterwards.
  Future<void> set({required bool wifiOnly}) async {
    await ref
        .read(sharedPreferencesProvider)
        .setBool(DownloadPreferenceKeys.wifiOnly, wifiOnly);
    state = wifiOnly;
  }
}
