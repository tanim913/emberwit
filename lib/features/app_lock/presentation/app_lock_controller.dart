import 'package:emberwit/core/preferences/general_preferences.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/core/security/authenticator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_lock_controller.g.dart';

/// What the app lock shows.
enum LockPhase {
  /// The app is usable.
  unlocked,

  /// The app is in the background: content is covered so the app switcher
  /// does not show it, but returning quickly needs no authentication.
  covered,

  /// The user must authenticate.
  locked,
}

/// Drives the app lock.
///
/// When the lock is on, the app starts locked. Leaving the app covers it at
/// once; coming back after [gracePeriod] or longer locks it.
@Riverpod(keepAlive: true)
class AppLockController extends _$AppLockController {
  DateTime? _leftAt;
  bool _authenticating = false;

  /// How long the app may stay in the background without locking.
  static const Duration gracePeriod = Duration(seconds: 30);

  @override
  LockPhase build() {
    final enabled = ref.watch(appLockEnabledProvider);
    // Turning the lock on in settings does not lock the running session;
    // a cold start with the lock on does.
    if (!enabled) return LockPhase.unlocked;
    return stateOrNull ?? LockPhase.locked;
  }

  /// Whether the system prompt is showing.
  bool get authenticating => _authenticating;

  /// The app went to the background.
  void onBackground() {
    if (!ref.read(appLockEnabledProvider)) return;
    _leftAt ??= ref.read(clockProvider).now();
    if (state == LockPhase.unlocked) state = LockPhase.covered;
  }

  /// The app came back to the foreground.
  void onForeground() {
    final leftAt = _leftAt;
    _leftAt = null;
    if (state != LockPhase.covered) return;
    final away = leftAt == null
        ? Duration.zero
        : ref.read(clockProvider).now().difference(leftAt);
    state = away >= gracePeriod ? LockPhase.locked : LockPhase.unlocked;
  }

  /// Shows the system prompt with [reason]; unlocks on success.
  Future<AuthenticationResult> unlock(String reason) async {
    if (_authenticating) return AuthenticationResult.failed;
    _authenticating = true;
    try {
      final result = await ref.read(authenticatorProvider).authenticate(reason);
      if (result == AuthenticationResult.success && ref.mounted) {
        state = LockPhase.unlocked;
      }
      return result;
    } finally {
      _authenticating = false;
    }
  }
}
