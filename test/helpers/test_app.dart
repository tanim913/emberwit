import 'dart:io';

import 'package:emberwit/app/app.dart';
import 'package:emberwit/app/runtime/runtime_supervisor.dart';
import 'package:emberwit/app/theme/app_theme.dart';
import 'package:emberwit/core/catalog/catalog_repository.dart';
import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/config/flavor_config.dart';
import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/logging/app_logger.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/core/runtime/device_conditions.dart';
import 'package:emberwit/core/runtime/runtime_status.dart';
import 'package:emberwit/core/security/authenticator.dart';
import 'package:emberwit/features/app_lock/data/app_lock_providers.dart';
import 'package:emberwit/features/app_lock/data/secure_window.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/device_profiler/fakes.dart';
import '../features/model_manager/fakes.dart';
import '../fixtures/catalog_fixtures.dart';
import '../fixtures/device_fixtures.dart';
import 'fake_runtime.dart';
import 'preferences.dart';

/// Provider overrides every widget test needs. The runtime supervisor is
/// created but not started, so no timers or observers outlive a test.
List<Override> baseOverrides({
  AppFlavor flavor = AppFlavor.dev,
  SharedPreferencesWithCache? preferences,
  Authenticator? authenticator,
  SecureWindow? secureWindow,
}) => [
  flavorConfigProvider.overrideWithValue(FlavorConfig.forFlavor(flavor)),
  appLoggerProvider.overrideWithValue(const SilentAppLogger()),
  appSupportDirectoryProvider.overrideWithValue(Directory.systemTemp),
  if (preferences != null)
    sharedPreferencesProvider.overrideWithValue(preferences),
  deviceConditionsSourceProvider.overrideWithValue(FakeConditionsSource()),
  runtimeSupervisorProvider.overrideWith(
    (ref) => RuntimeSupervisor(
      engine: () => null,
      conditions: ref.watch(deviceConditionsSourceProvider),
      status: ref.read(runtimeStatusProvider.notifier),
    ),
  ),
  authenticatorProvider.overrideWithValue(authenticator ?? FakeAuthenticator()),
  secureWindowProvider.overrideWithValue(secureWindow ?? FakeSecureWindow()),
];

/// Overrides for the onboarding screens: a profiled 8 GB phone, a one model
/// catalog and an empty library.
List<Override> onboardingOverrides({FakeModelLibrary? library}) => [
  deviceProfileRepositoryProvider.overrideWithValue(
    FakeDeviceProfileRepository(
      cached: profile(benchmark: benchmarkAt(120)),
      refreshed: profile(benchmark: benchmarkAt(120)),
    ),
  ),
  catalogRepositoryProvider.overrideWithValue(
    FakeCatalogRepository(
      CatalogSnapshot(
        catalog: ModelCatalog(
          schemaVersion: 1,
          catalogVersion: 1,
          generatedAt: DateTime.utc(2026, 9, 24),
          models: [entry(id: 'qwen3-0.6b-q4', size: 484220320)],
        ),
        source: CatalogSource.bundled,
        loadedAt: DateTime.utc(2026, 9, 24),
      ),
    ),
  ),
  modelLibraryProvider.overrideWithValue(library ?? FakeModelLibrary()),
];

extension PumpApp on WidgetTester {
  /// Pumps the full [EmberwitApp] with test overrides. Without
  /// [preferences], the app starts on onboarding.
  Future<ProviderContainer> pumpEmberwitApp({
    AppFlavor flavor = AppFlavor.dev,
    List<Override> overrides = const [],
    SharedPreferencesWithCache? preferences,
  }) async {
    final prefs = preferences ?? (await runAsync(inMemoryPreferences))!;
    final container = ProviderContainer.test(
      overrides: [
        ...baseOverrides(flavor: flavor, preferences: prefs),
        ...onboardingOverrides(),
        ...overrides,
      ],
    );
    await pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EmberwitApp(),
      ),
    );
    await pumpAndSettle();
    return container;
  }

  /// Pumps a single screen with theme, localization and providers, without
  /// the router.
  Future<void> pumpScreen(
    Widget screen, {
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
    AppFlavor flavor = AppFlavor.dev,
    List<Override> overrides = const [],
  }) async {
    final prefs = (await runAsync(inMemoryPreferences))!;
    await pumpWidget(
      ProviderScope(
        overrides: [
          ...baseOverrides(flavor: flavor, preferences: prefs),
          ...overrides,
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: screen,
        ),
      ),
    );
    await pumpAndSettle();
  }
}
