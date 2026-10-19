/// Product wide constants.
///
/// The product name lives here and nowhere else in Dart code, so renaming the
/// app is a one line change here plus the native labels listed in README.md.
abstract final class AppConstants {
  /// Product name shown in the UI. Not translated: it is a brand.
  static const String appName = 'Emberwit';

  /// Locale used when the device locale is not supported.
  static const String fallbackLanguageCode = 'en';
}
