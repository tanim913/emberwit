import 'package:emberwit/core/preferences/general_preferences.dart';
import 'package:emberwit/core/preferences/preference_keys.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/core/security/authenticator.dart';
import 'package:emberwit/core/utils/clock.dart';
import 'package:emberwit/features/app_lock/data/local_auth_authenticator.dart';
import 'package:emberwit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

import '../../helpers/fake_runtime.dart';
import '../../helpers/preferences.dart';

void main() {
  late FixedClock clock;
  late FakeAuthenticator auth;

  Future<ProviderContainer> container({required bool lockOn}) async {
    clock = FixedClock(DateTime.utc(2026, 10, 3));
    auth = FakeAuthenticator();
    final prefs = await inMemoryPreferences({PreferenceKeys.appLock: lockOn});
    return ProviderContainer.test(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(clock),
        authenticatorProvider.overrideWithValue(auth),
      ],
    );
  }

  test('without the lock the app is always usable', () async {
    final c = await container(lockOn: false);
    expect(c.read(appLockControllerProvider), LockPhase.unlocked);
    c.read(appLockControllerProvider.notifier).onBackground();
    expect(c.read(appLockControllerProvider), LockPhase.unlocked);
  });

  test('with the lock the app starts locked and unlocks', () async {
    final c = await container(lockOn: true);
    expect(c.read(appLockControllerProvider), LockPhase.locked);
    final result = await c
        .read(appLockControllerProvider.notifier)
        .unlock('Unlock');
    expect(result, AuthenticationResult.success);
    expect(auth.prompts, ['Unlock']);
    expect(c.read(appLockControllerProvider), LockPhase.unlocked);
  });

  test('a failed attempt stays locked', () async {
    final c = await container(lockOn: true);
    auth.result = AuthenticationResult.failed;
    await c.read(appLockControllerProvider.notifier).unlock('Unlock');
    expect(c.read(appLockControllerProvider), LockPhase.locked);
  });

  test('leaving covers at once; a quick return needs no unlock', () async {
    final c = await container(lockOn: true);
    final lock = c.read(appLockControllerProvider.notifier);
    await lock.unlock('Unlock');
    lock.onBackground();
    expect(c.read(appLockControllerProvider), LockPhase.covered);
    clock.advance(const Duration(seconds: 10));
    lock.onForeground();
    expect(c.read(appLockControllerProvider), LockPhase.unlocked);
  });

  test('returning after the grace period locks', () async {
    final c = await container(lockOn: true);
    final lock = c.read(appLockControllerProvider.notifier);
    await lock.unlock('Unlock');
    lock.onBackground();
    clock.advance(AppLockController.gracePeriod);
    lock.onForeground();
    expect(c.read(appLockControllerProvider), LockPhase.locked);
  });

  test('turning the lock off unlocks; turning it on does not lock', () async {
    final c = await container(lockOn: true);
    expect(c.read(appLockControllerProvider), LockPhase.locked);
    await c.read(appLockEnabledProvider.notifier).set(enabled: false);
    expect(c.read(appLockControllerProvider), LockPhase.unlocked);
    await c.read(appLockEnabledProvider.notifier).set(enabled: true);
    expect(c.read(appLockControllerProvider), LockPhase.unlocked);
  });

  test('maps plugin errors to results', () {
    expect(
      authenticationResultFor(LocalAuthExceptionCode.noCredentialsSet),
      AuthenticationResult.unavailable,
    );
    expect(
      authenticationResultFor(LocalAuthExceptionCode.noBiometricHardware),
      AuthenticationResult.unavailable,
    );
    expect(
      authenticationResultFor(LocalAuthExceptionCode.temporaryLockout),
      AuthenticationResult.lockedOut,
    );
    expect(
      authenticationResultFor(LocalAuthExceptionCode.biometricLockout),
      AuthenticationResult.lockedOut,
    );
    expect(
      authenticationResultFor(LocalAuthExceptionCode.userCanceled),
      AuthenticationResult.failed,
    );
  });
}
