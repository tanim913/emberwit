import 'package:emberwit/app/app.dart';
import 'package:emberwit/app/providers/feature_bindings.dart';
import 'package:emberwit/core/config/flavor_config.dart';
import 'package:emberwit/core/logging/app_logger.dart';
import 'package:emberwit/core/preferences/preference_keys.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Starts the app.
///
/// Order matters: error handlers are installed before anything else runs, the
/// flavor is resolved before the first frame, and the first frame is built
/// with every required provider already overridden. Nothing slow happens
/// here, which keeps cold start fast.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = createDefaultLogger();
  installErrorHandlers(logger);
  registerBundledLicenses();

  final flavor = FlavorConfig.resolve(appFlavor, isRelease: kReleaseMode);
  switch (flavor) {
    case Ok(:final value):
      final config = FlavorConfig.forFlavor(value);
      logger.info('Starting ${config.flavor.name} build');
      // A few milliseconds; lets every provider use the path synchronously.
      final support = await getApplicationSupportDirectory();
      final preferences = await SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(
          allowList: PreferenceKeys.all,
        ),
      );
      runApp(
        ProviderScope(
          overrides: [
            flavorConfigProvider.overrideWithValue(config),
            appLoggerProvider.overrideWithValue(logger),
            appSupportDirectoryProvider.overrideWithValue(support),
            sharedPreferencesProvider.overrideWithValue(preferences),
            ...featureBindings(),
          ],
          child: const EmberwitApp(),
        ),
      );
    case Err(:final failure):
      logger.error('Invalid build configuration', failure);
      runApp(const ConfigurationErrorApp());
  }
}

/// Routes uncaught framework and platform errors to [logger] instead of
/// crashing silently. Error details are logged, never user content.
@visibleForTesting
void installErrorHandlers(AppLogger logger) {
  FlutterError.onError = (details) {
    logger.error('Flutter framework error', details.exception, details.stack);
    if (kDebugMode) FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    logger.error('Uncaught asynchronous error', error, stackTrace);
    return true;
  };
}

/// Adds licenses of bundled assets (fonts) to the license registry so they
/// appear on the licenses screen next to package licenses.
@visibleForTesting
void registerBundledLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const [
      'Noto Sans',
      'Noto Sans Bengali',
      'Noto Sans Mono',
    ], text);
    final katex = await rootBundle.loadString('assets/fonts/KaTeX-LICENSE.txt');
    yield LicenseEntryWithLineBreaks(const ['KaTeX fonts'], katex);
  });
}
