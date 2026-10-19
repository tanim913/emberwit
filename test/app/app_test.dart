import 'package:emberwit/app/app.dart';
import 'package:emberwit/core/config/flavor_config.dart';
import 'package:emberwit/core/preferences/app_preferences.dart';
import 'package:emberwit/features/onboarding/presentation/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  group('EmberwitApp', () {
    testWidgets('starts on onboarding in English', (tester) async {
      await tester.pumpEmberwitApp();
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.text('Welcome to Emberwit'), findsOneWidget);
    });

    testWidgets('switches to Bengali when the locale preference changes', (
      tester,
    ) async {
      final container = await tester.pumpEmberwitApp();
      await tester.runAsync(
        () => container
            .read(appPreferencesProvider.notifier)
            .setLocale(const Locale('bn')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Emberwit-এ স্বাগতম'), findsOneWidget);
    });

    testWidgets('applies the theme mode preference', (tester) async {
      final container = await tester.pumpEmberwitApp();
      await tester.runAsync(
        () => container
            .read(appPreferencesProvider.notifier)
            .setThemeMode(ThemeMode.dark),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(OnboardingPage));
      expect(Theme.of(context).brightness, Brightness.dark);
    });

    testWidgets('shows a banner on dev and staging, not on prod', (
      tester,
    ) async {
      String bannerMessage() =>
          tester.widget<Banner>(find.byType(Banner)).message;

      await tester.pumpEmberwitApp();
      expect(bannerMessage(), 'DEV');

      await tester.pumpEmberwitApp(flavor: AppFlavor.staging);
      expect(bannerMessage(), 'STAGING');

      await tester.pumpEmberwitApp(flavor: AppFlavor.prod);
      expect(find.byType(Banner), findsNothing);
    });

    testWidgets('uses the flavor app name as the window title', (tester) async {
      await tester.pumpEmberwitApp(flavor: AppFlavor.staging);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.title, 'Emberwit Staging');
    });
  });

  group('ConfigurationErrorApp', () {
    testWidgets('explains the problem without needing providers', (
      tester,
    ) async {
      await tester.pumpWidget(const ConfigurationErrorApp());
      await tester.pumpAndSettle();
      expect(find.text('Something is wrong with this build'), findsOneWidget);
    });
  });

  group('resolveLocale', () {
    const supported = [Locale('en'), Locale('bn')];

    test('matches by language code', () {
      expect(
        resolveLocale(const [Locale('bn', 'BD')], supported),
        const Locale('bn'),
      );
      expect(
        resolveLocale(const [Locale('en', 'GB')], supported),
        const Locale('en'),
      );
    });

    test('uses the first supported preferred language', () {
      expect(
        resolveLocale(const [Locale('fr'), Locale('bn')], supported),
        const Locale('bn'),
      );
    });

    test('falls back to English', () {
      expect(
        resolveLocale(const [Locale('fr')], supported),
        const Locale('en'),
      );
      expect(resolveLocale(null, supported), const Locale('en'));
    });
  });
}
