import 'package:emberwit/core/security/authenticator.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// [Authenticator] using the system prompt: biometrics with the device PIN,
/// pattern or password as fallback. Nothing about the user's biometrics ever
/// reaches the app; the OS only reports success or failure.
final class LocalAuthAuthenticator implements Authenticator {
  /// Creates the authenticator.
  new([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }

  @override
  Future<AuthenticationResult> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      return ok ? AuthenticationResult.success : AuthenticationResult.failed;
    } on LocalAuthException catch (e) {
      return authenticationResultFor(e.code);
    } on PlatformException {
      return AuthenticationResult.failed;
    }
  }
}

/// Maps a plugin error code to an [AuthenticationResult].
AuthenticationResult authenticationResultFor(LocalAuthExceptionCode code) =>
    switch (code) {
      LocalAuthExceptionCode.noCredentialsSet ||
      LocalAuthExceptionCode.noBiometricHardware ||
      LocalAuthExceptionCode.noBiometricsEnrolled ||
      LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
        AuthenticationResult.unavailable,
      LocalAuthExceptionCode.temporaryLockout ||
      LocalAuthExceptionCode.biometricLockout => AuthenticationResult.lockedOut,
      _ => AuthenticationResult.failed,
    };
