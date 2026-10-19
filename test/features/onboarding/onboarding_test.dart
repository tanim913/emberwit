import 'package:emberwit/core/catalog/catalog_repository.dart';
import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/preferences/general_preferences.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/features/onboarding/presentation/onboarding_controller.dart';
import 'package:emberwit/features/onboarding/presentation/onboarding_page.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../fixtures/catalog_fixtures.dart';
import '../../fixtures/device_fixtures.dart';
import '../../helpers/preferences.dart';
import '../../helpers/test_app.dart';
import '../chat/domain/chat_responder_test.dart' show installed;
import '../device_profiler/fakes.dart';
import '../model_manager/fakes.dart';

CatalogSnapshot _catalog(List<CatalogEntry> models) => CatalogSnapshot(
  catalog: ModelCatalog(
    schemaVersion: 1,
    catalogVersion: 1,
    generatedAt: DateTime.utc(2026),
    models: models,
  ),
  source: CatalogSource.bundled,
  loadedAt: DateTime.utc(2026),
);

List<Override> _overrides({
  required FakeModelLibrary library,
  List<CatalogEntry>? models,
  bool profiled = true,
}) => [
  deviceProfileRepositoryProvider.overrideWithValue(
    FakeDeviceProfileRepository(
      cached: profiled ? profile(benchmark: benchmarkAt(120)) : null,
      refreshFailure: profiled ? null : const DeviceProfilingFailure('x'),
    ),
  ),
  catalogRepositoryProvider.overrideWithValue(
    FakeCatalogRepository(
      _catalog(
        models ??
            [
              entry(id: 'restricted', agreement: true, size: 300000000),
              entry(id: 'open', size: 400000000),
            ],
      ),
    ),
  ),
  modelLibraryProvider.overrideWithValue(library),
];

void main() {
  group('OnboardingController', () {
    Future<ProviderContainer> container(
      FakeModelLibrary library, {
      List<CatalogEntry>? models,
      bool profiled = true,
    }) async {
      final c = ProviderContainer.test(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await inMemoryPreferences(),
          ),
          ..._overrides(library: library, models: models, profiled: profiled),
        ],
      )..listen(onboardingControllerProvider, (_, _) {});
      // Let the profile, catalog and library load.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return c;
    }

    test('suggests a model without a license agreement', () async {
      final c = await container(FakeModelLibrary());
      final state = c.read(onboardingControllerProvider);
      expect(state.profiling, isFalse);
      expect(state.tier, isNotNull);
      expect(state.suggested?.id, 'open');
      expect(state.recommendation?.modelId, 'open');
      expect(state.hasModel, isFalse);
    });

    test('downloads the suggestion once', () async {
      final library = FakeModelLibrary();
      final c = await container(library);
      final controller = c.read(onboardingControllerProvider.notifier);
      await controller.downloadSuggested();
      await controller.downloadSuggested();
      expect(library.calls, ['download:open']);
      expect(c.read(onboardingControllerProvider).downloadStarted, isTrue);
    });

    test('reports a failed download', () async {
      final library = FakeModelLibrary()
        ..nextFailure = const DownloadFailure(
          DownloadFailureReason.insufficientStorage,
        );
      final c = await container(library);
      await c.read(onboardingControllerProvider.notifier).downloadSuggested();
      final state = c.read(onboardingControllerProvider);
      expect(state.downloadStarted, isFalse);
      expect(state.failure, isA<DownloadFailure>());
    });

    test('knows when a model is already installed', () async {
      final c = await container(
        FakeModelLibrary(LibraryState(installed: [installed('open')])),
      );
      expect(c.read(onboardingControllerProvider).hasModel, isTrue);
    });

    test('suggests nothing without a profile', () async {
      final c = await container(FakeModelLibrary(), profiled: false);
      final state = c.read(onboardingControllerProvider);
      expect(state.profile, isNull);
      expect(state.suggested, isNull);
    });

    test('finishing marks onboarding done', () async {
      final c = await container(FakeModelLibrary());
      await c.read(onboardingControllerProvider.notifier).finish();
      expect(c.read(onboardingCompletedProvider), isTrue);
    });
  });

  group('OnboardingPage', () {
    Future<(FakeModelLibrary, GoRouter)> pump(WidgetTester tester) async {
      final library = FakeModelLibrary();
      final router = GoRouter(
        initialLocation: '/welcome',
        routes: [
          GoRoute(path: '/welcome', builder: (_, _) => const OnboardingPage()),
          GoRoute(path: '/chats', builder: (_, _) => const Text('Chats')),
          GoRoute(path: '/models', builder: (_, _) => const Text('Models')),
        ],
      );
      addTearDown(router.dispose);
      final prefs = (await tester.runAsync(inMemoryPreferences))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...baseOverrides(preferences: prefs),
            ..._overrides(library: library),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (library, router);
    }

    testWidgets('walks through four steps and downloads the suggestion', (
      tester,
    ) async {
      final (library, _) = await pump(tester);
      expect(find.text('Welcome to Emberwit'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pumpAndSettle();
      expect(find.text('How it works'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onboarding-tier')), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onboarding-next')), findsNothing);
      expect(find.byKey(const Key('onboarding-suggested')), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding-download')));
      await tester.pumpAndSettle();
      expect(library.calls, ['download:open']);
      expect(
        find.text('Downloading. It continues in the background.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('onboarding-finish')));
      await tester.pumpAndSettle();
      expect(find.text('Chats'), findsOneWidget);
    });

    testWidgets('skip finishes onboarding at once', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('onboarding-skip')));
      await tester.pumpAndSettle();
      expect(find.text('Chats'), findsOneWidget);
    });

    testWidgets('see all models opens the models screen', (tester) async {
      final (_, router) = await pump(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('onboarding-next')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('onboarding-browse')));
      await tester.pumpAndSettle();
      expect(find.text('Models'), findsOneWidget);
      expect(router.canPop(), isTrue);
    });
  });
}
