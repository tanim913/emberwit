import 'package:flutter/services.dart';

/// Marks the app window as secure while the lock screen shows: on Android,
/// `FLAG_SECURE` blocks screenshots, screen recording and the recent apps
/// thumbnail. Elsewhere it does nothing.
abstract interface class SecureWindow {
  /// Turns protection on or off.
  Future<void> setSecure({required bool secure});
}

/// [SecureWindow] over the `app.emberwit/window` channel (MainActivity).
final class PlatformSecureWindow implements SecureWindow {
  /// Creates the window controller.
  const new([this._channel = const MethodChannel('app.emberwit/window')]);

  final MethodChannel _channel;

  @override
  Future<void> setSecure({required bool secure}) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } on MissingPluginException {
      // iOS and desktop: not available, nothing to do.
    } on PlatformException {
      // Best effort: the lock screen still hides the content.
    }
  }
}
