import 'package:emberwit/app/router/app_router.dart';
import 'package:emberwit/app/runtime/runtime_supervisor.dart';
import 'package:emberwit/app/shell/flavor_banner.dart';
import 'package:emberwit/app/shell/launch_actions.dart';
import 'package:emberwit/app/theme/app_theme.dart';
import 'package:emberwit/core/constants/app_constants.dart';
import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:emberwit/core/preferences/app_preferences.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/features/app_lock/presentation/app_lock_gate.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root widget of the app.
///
/// Must sit under a `ProviderScope` that overrides `flavorConfigProvider`.
class EmberwitApp extends ConsumerWidget {
  /// Creates the app root.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider());
    final preferences = ref.watch(appPreferencesProvider);
    final config = ref.watch(flavorConfigProvider);
    // Watches heat, battery and memory for the whole app lifetime.
    ref.watch(runtimeSupervisorProvider);
    return MaterialApp.router(
      title: config.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: preferences.themeMode,
      locale: preferences.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      localeListResolutionCallback: resolveLocale,
      builder: (context, child) => FlavorBanner(
        child: AppLockGate(
          child: LaunchActions(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}

/// Picks the first supported language from the user's [preferred] locales,
/// falling back to English.
///
/// Matching is by language code only, so `bn_IN` and `bn_BD` both get Bengali
/// and `en_GB` gets English.
Locale resolveLocale(List<Locale>? preferred, Iterable<Locale> supported) {
  for (final locale in preferred ?? const <Locale>[]) {
    for (final candidate in supported) {
      if (candidate.languageCode == locale.languageCode) return candidate;
    }
  }
  return const Locale(AppConstants.fallbackLanguageCode);
}

/// Minimal app shown instead of [EmberwitApp] when the build configuration is
/// invalid (for example a release build without a known flavor).
///
/// It deliberately has no providers and no network access.
class ConfigurationErrorApp extends StatelessWidget {
  /// Creates the configuration error app.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      localeListResolutionCallback: resolveLocale,
      home: const _ConfigurationErrorPage(),
    );
  }
}

class _ConfigurationErrorPage extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.configurationErrorTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.configurationErrorBody,
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
