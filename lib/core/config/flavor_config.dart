import 'package:emberwit/core/constants/app_constants.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'flavor_config.freezed.dart';

/// Build flavors. Names match the Android `productFlavors` and the iOS
/// schemes, which is what Flutter reports through `appFlavor`.
enum AppFlavor {
  /// Local development. Debug tools on, dev catalog.
  dev,

  /// Pre-release testing against the staging catalog.
  staging,

  /// Store builds.
  prod,
}

/// Environment specific configuration for the running build.
///
/// Features read it through `flavorConfigProvider` and never check the flavor
/// directly for behaviour, only for configuration values.
@freezed
abstract class FlavorConfig with _$FlavorConfig {
  /// Creates a configuration. Prefer [FlavorConfig.forFlavor].
  const factory({
    required AppFlavor flavor,

    /// Name shown in the UI for this build.
    required String appName,

    /// URL of the signed remote model catalog manifest.
    required Uri catalogUrl,

    /// Whether a corner banner marks this build as non production.
    required bool showBanner,

    /// Whether developer screens (such as the engine debug screen) are
    /// reachable. Never in production.
    required bool enableDebugTools,

    /// SPKI pins (`sha256/<base64>`) for the catalog host. Empty until the
    /// catalog host is live; production builds must set a primary and a
    /// backup pin (see SECURITY.md).
    @Default(<String>[]) List<String> catalogCertificatePins,
  }) = _FlavorConfig;

  /// The configuration for [flavor].
  factory forFlavor(AppFlavor flavor) => switch (flavor) {
    AppFlavor.dev => FlavorConfig(
      flavor: flavor,
      appName: '${AppConstants.appName} Dev',
      catalogUrl: Uri.parse(
        'https://tanim913.github.io/emberwit/catalog/dev/manifest.json',
      ),
      showBanner: true,
      enableDebugTools: true,
    ),
    AppFlavor.staging => FlavorConfig(
      flavor: flavor,
      appName: '${AppConstants.appName} Staging',
      catalogUrl: Uri.parse(
        'https://tanim913.github.io/emberwit/catalog/staging/manifest.json',
      ),
      showBanner: true,
      enableDebugTools: true,
    ),
    AppFlavor.prod => FlavorConfig(
      flavor: flavor,
      appName: AppConstants.appName,
      catalogUrl: Uri.parse(
        'https://tanim913.github.io/emberwit/catalog/v1/manifest.json',
      ),
      showBanner: false,
      enableDebugTools: false,
    ),
  };

  /// Resolves the flavor reported by the platform ([rawFlavor], normally
  /// `appFlavor` from `package:flutter/services.dart`).
  ///
  /// A missing flavor falls back to [AppFlavor.dev] outside release mode, so
  /// `flutter run` and `flutter test` work without `--flavor`. In release mode
  /// a missing or unknown flavor is a [ConfigurationFailure]: shipping a build
  /// pointed at the wrong catalog must never happen silently.
  static Result<AppFlavor> resolve(
    String? rawFlavor, {
    required bool isRelease,
  }) {
    if (rawFlavor == null || rawFlavor.isEmpty) {
      return isRelease
          ? const Err(ConfigurationFailure('Release build without a flavor'))
          : const Ok(AppFlavor.dev);
    }
    for (final flavor in AppFlavor.values) {
      if (flavor.name == rawFlavor) return Ok(flavor);
    }
    return Err(ConfigurationFailure('Unknown flavor "$rawFlavor"'));
  }
}
