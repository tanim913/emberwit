@Tags(['golden'])
library;

import 'package:emberwit/core/chat/chat_archive.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/features/app_lock/presentation/app_lock_gate.dart';
import 'package:emberwit/features/onboarding/presentation/onboarding_page.dart';
import 'package:emberwit/features/settings/data/settings_providers.dart';
import 'package:emberwit/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/chat/domain/chat_responder_test.dart' show installed;
import '../features/model_manager/fakes.dart';
import '../features/settings/fakes.dart';
import '../helpers/test_app.dart';

Future<void> _phone(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  for (final locale in const [Locale('en'), Locale('bn')]) {
    for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
      final name = '${locale.languageCode}_${mode.name}';

      testWidgets('onboarding $name', (tester) async {
        await _phone(tester);
        await tester.pumpScreen(
          const OnboardingPage(),
          locale: locale,
          themeMode: mode,
          overrides: onboardingOverrides(),
        );
        await expectLater(
          find.byType(OnboardingPage),
          matchesGoldenFile('goldens/onboarding_$name.png'),
        );
      });

      testWidgets('settings $name', (tester) async {
        await _phone(tester);
        await tester.pumpScreen(
          const SettingsPage(),
          locale: locale,
          themeMode: mode,
          overrides: [
            chatArchiveProvider.overrideWithValue(FakeChatArchive()),
            modelLibraryProvider.overrideWithValue(
              FakeModelLibrary(
                LibraryState(installed: [installed('qwen3-0.6b-q4')]),
              ),
            ),
            appVersionProvider.overrideWith((ref) async => '0.1.0 (1)'),
          ],
        );
        await expectLater(
          find.byType(SettingsPage),
          matchesGoldenFile('goldens/settings_$name.png'),
        );
      });

      testWidgets('lock screen $name', (tester) async {
        await _phone(tester);
        await tester.pumpScreen(
          const LockScreen(locked: true),
          locale: locale,
          themeMode: mode,
        );
        await expectLater(
          find.byType(LockScreen),
          matchesGoldenFile('goldens/lock_$name.png'),
        );
      });
    }
  }
}
