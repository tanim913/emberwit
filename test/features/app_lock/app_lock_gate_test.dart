import 'package:emberwit/app/theme/app_theme.dart';
import 'package:emberwit/core/preferences/preference_keys.dart';
import 'package:emberwit/core/security/authenticator.dart';
import 'package:emberwit/features/app_lock/presentation/app_lock_gate.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_runtime.dart';
import '../../helpers/preferences.dart';
import '../../helpers/test_app.dart';

Future<(FakeAuthenticator, FakeSecureWindow)> _pump(
  WidgetTester tester, {
  required bool lockOn,
  AuthenticationResult result = AuthenticationResult.success,
}) async {
  final prefs = (await tester.runAsync(
    () => inMemoryPreferences({PreferenceKeys.appLock: lockOn}),
  ))!;
  final auth = FakeAuthenticator(result: result);
  final window = FakeSecureWindow();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...baseOverrides(
          preferences: prefs,
          authenticator: auth,
          secureWindow: window,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => AppLockGate(child: child!),
        home: const Scaffold(body: Text('Secret chat')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (auth, window);
}

void main() {
  testWidgets('no lock screen when the lock is off', (tester) async {
    final (auth, window) = await _pump(tester, lockOn: false);
    expect(find.byKey(const Key('lock-screen')), findsNothing);
    expect(find.text('Secret chat'), findsOneWidget);
    expect(auth.prompts, isEmpty);
    expect(window.changes, isEmpty);
  });

  testWidgets('asks right away, protects the window, then opens', (
    tester,
  ) async {
    final (auth, window) = await _pump(tester, lockOn: true);
    // The prompt was shown automatically and succeeded.
    expect(auth.prompts, ['Unlock Emberwit']);
    expect(find.byKey(const Key('lock-screen')), findsNothing);
    // FLAG_SECURE only while the lock screen showed.
    expect(window.changes, [true, false]);
  });

  testWidgets('stays locked after a failed attempt and can retry', (
    tester,
  ) async {
    final (auth, window) = await _pump(
      tester,
      lockOn: true,
      result: AuthenticationResult.failed,
    );
    expect(find.byKey(const Key('lock-screen')), findsOneWidget);
    expect(find.text('Not recognised. Try again.'), findsOneWidget);
    expect(window.secure, isTrue);
    // Content under the lock is hidden from screen readers.
    expect(find.bySemanticsLabel('Secret chat'), findsNothing);

    auth.result = AuthenticationResult.success;
    await tester.tap(find.byKey(const Key('unlock')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lock-screen')), findsNothing);
    expect(window.secure, isFalse);
  });

  testWidgets('explains a missing screen lock', (tester) async {
    await _pump(tester, lockOn: true, result: AuthenticationResult.unavailable);
    expect(find.textContaining('Set up a screen lock'), findsOneWidget);
  });

  testWidgets('covers the app in the background', (tester) async {
    await _pump(tester, lockOn: true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    // Drawn while frames still run, before the app is hidden.
    expect(find.byKey(const Key('lock-screen')), findsOneWidget);
    expect(find.byKey(const Key('unlock')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lock-screen')), findsNothing);
  });
}
