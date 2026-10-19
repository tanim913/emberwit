import 'dart:io';

import 'package:flutter/services.dart';

/// Excludes a directory from iCloud backup on iOS; does nothing elsewhere
/// (Android excludes it through its backup rules).
class BackupExclusion {
  /// Creates the helper.
  const new([this._channel = const MethodChannel('app.emberwit/storage')]);

  final MethodChannel _channel;

  /// Flags [directory] (and its contents) as not backed up.
  Future<void> exclude(Directory directory) async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod<bool>('excludeFromBackup', {
      'path': directory.path,
    });
  }
}
