import 'package:emberwit/core/security/authenticator.dart';
import 'package:emberwit/features/app_lock/data/local_auth_authenticator.dart';
import 'package:emberwit/features/app_lock/data/secure_window.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_lock_providers.g.dart';

/// The system authenticator. `featureBindings()` exposes it as the shared
/// `authenticatorProvider`.
@Riverpod(keepAlive: true)
Authenticator localAuthenticator(Ref ref) => LocalAuthAuthenticator();

/// Window protection for the lock screen.
@Riverpod(keepAlive: true)
SecureWindow secureWindow(Ref ref) => const PlatformSecureWindow();
