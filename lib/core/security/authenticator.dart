import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'authenticator.g.dart';

/// Result of asking the user to prove it is them.
enum AuthenticationResult {
  /// The user authenticated.
  success,

  /// The user cancelled or failed.
  failed,

  /// The device has no biometrics or screen lock set up.
  unavailable,

  /// Too many attempts; the OS locked authentication for a while.
  lockedOut,
}

/// Device owner authentication (biometrics, or the device PIN, pattern or
/// password). Implemented by the app_lock feature, wired in
/// `featureBindings()`.
abstract interface class Authenticator {
  /// Whether the device has biometrics or a screen lock that can be used.
  Future<bool> isAvailable();

  /// Shows the system prompt with [reason].
  Future<AuthenticationResult> authenticate(String reason);
}

/// The authenticator. Overridden by `featureBindings()`.
@Riverpod(keepAlive: true)
Authenticator authenticator(Ref ref) => throw StateError(
  'authenticatorProvider must be overridden by featureBindings().',
);
