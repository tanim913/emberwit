import 'dart:io';

import 'package:emberwit/app/debug/engine_debug_controller.dart';
import 'package:emberwit/app/debug/engine_debug_page.dart';
import 'package:emberwit/app/router/app_router.dart';
import 'package:emberwit/app/shell/not_found_page.dart';
import 'package:emberwit/app/theme/app_theme.dart';
import 'package:emberwit/core/config/flavor_config.dart';
import 'package:emberwit/core/navigation/app_routes.dart';
import 'package:emberwit/core/preferences/general_preferences.dart';
import 'package:emberwit/engine/engine_providers.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:emberwit/features/chat/presentation/chat_controllers.dart';
import 'package:emberwit/features/chat/presentation/conversations_page.dart';
import 'package:emberwit/features/device_profiler/presentation/device_check_page.dart';
import 'package:emberwit/features/onboarding/presentation/onboarding_page.dart';
import 'package:emberwit/features/settings/presentation/settings_page.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_inference_engine.dart';
import '../../helpers/preferences.dart';
import '../../helpers/test_app.dart';

Future<ProviderContainer> _pumpRouter(
  WidgetTester tester,
  String location, {
  AppFlavor flavor = AppFlavor.dev,
  bool onboarded = true,
}) async {
  tester.view
    ..physicalSize = const Size(1080, 6000)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final preferences = (await tester.runAsync(
    onboarded ? onboardedPreferences : inMemoryPreferences,
  ))!;
  final container = ProviderContainer.test(
    overrides: [
      ...baseOverrides(flavor: flavor, preferences: preferences),
      ...onboardingOverrides(),
      inferenceEngineProvider.overrideWithValue(FakeInferenceEngine()),
      conversationsProvider.overrideWith(
        (ref, query) => Stream.value(const <Conversation>[]),
      ),
      debugModelsDirectoryProvider.overrideWith(
        (ref) async => Directory.systemTemp,
      ),
    ],
  );
  final router = container.read(appRouterProvider(initialLocation: location));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('appRouter', () {
    testWidgets('every location shows onboarding until it is done', (
      tester,
    ) async {
      await _pumpRouter(tester, AppRoutes.settings, onboarded: false);
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.byType(SettingsPage), findsNothing);
    });

    testWidgets('finishing onboarding leaves it for good', (tester) async {
      final container = await _pumpRouter(
        tester,
        AppRoutes.home,
        onboarded: false,
      );
      await tester.runAsync(
        () => container.read(onboardingCompletedProvider.notifier).complete(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.byType(ConversationsPage), findsOneWidget);
      // Onboarding is no longer reachable.
      container.read(appRouterProvider()).go(AppRoutes.onboarding);
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsNothing);
    });

    testWidgets('home is the conversation list', (tester) async {
      await _pumpRouter(tester, AppRoutes.home);
      expect(find.byType(ConversationsPage), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
    });

    testWidgets('unknown route shows not found and can go home', (
      tester,
    ) async {
      await _pumpRouter(tester, '/does-not-exist');
      expect(find.byType(NotFoundPage), findsOneWidget);
      expect(find.text('Page not found'), findsOneWidget);
      await tester.tap(find.text('Go to home'));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationsPage), findsOneWidget);
    });

    testWidgets('settings reach the device check in every flavor', (
      tester,
    ) async {
      await _pumpRouter(tester, AppRoutes.settings, flavor: AppFlavor.prod);
      await tester.tap(find.byKey(const Key('settings-device-check')));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceCheckPage), findsOneWidget);
    });

    testWidgets('debug builds reach the engine debug screen', (tester) async {
      await _pumpRouter(tester, AppRoutes.settings);
      await tester.tap(find.byKey(const Key('open-engine-debug')));
      await tester.pumpAndSettle();
      expect(find.byType(EngineDebugPage), findsOneWidget);
    });

    testWidgets('production builds have no debug route or button', (
      tester,
    ) async {
      await _pumpRouter(tester, AppRoutes.settings, flavor: AppFlavor.prod);
      expect(find.byKey(const Key('open-engine-debug')), findsNothing);
      await _pumpRouter(tester, AppRoutes.engineDebug, flavor: AppFlavor.prod);
      expect(find.byType(EngineDebugPage), findsNothing);
      expect(find.byType(NotFoundPage), findsOneWidget);
    });
  });
}
