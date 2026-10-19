import 'package:emberwit/core/runtime/device_conditions.dart';
import 'package:emberwit/core/security/authenticator.dart';
import 'package:emberwit/features/app_lock/data/secure_window.dart';

/// Conditions source returning [conditions], or throwing [error].
class FakeConditionsSource implements DeviceConditionsSource {
  new([this.conditions = const DeviceConditions()]);

  DeviceConditions conditions;
  Error? error;
  int reads = 0;

  @override
  Future<DeviceConditions> read() async {
    reads++;
    if (error case final e?) throw e;
    return conditions;
  }
}

/// Authenticator answering [result] and recording prompts.
class FakeAuthenticator implements Authenticator {
  new({this.available = true, this.result = AuthenticationResult.success});

  bool available;
  AuthenticationResult result;
  final List<String> prompts = [];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AuthenticationResult> authenticate(String reason) async {
    prompts.add(reason);
    return result;
  }
}

/// Records [SecureWindow] changes.
class FakeSecureWindow implements SecureWindow {
  final List<bool> changes = [];

  bool get secure => changes.isNotEmpty && changes.last;

  @override
  Future<void> setSecure({required bool secure}) async => changes.add(secure);
}
