import 'dart:convert';
import 'dart:io';

import 'package:emberwit/core/device/device_profile.dart';

/// Persists the last [DeviceProfile].
abstract interface class DeviceProfileCache {
  /// The saved profile, or `null` when none is saved or it is unreadable.
  Future<DeviceProfile?> read();

  /// Saves [profile], replacing the previous one.
  Future<void> write(DeviceProfile profile);
}

/// [DeviceProfileCache] in a JSON file in app private storage.
///
/// Writes go to a temporary file first and are renamed into place, so a
/// crash mid-write never leaves a corrupt cache. The profile holds no user
/// content, only hardware facts and benchmark numbers.
final class FileDeviceProfileCache implements DeviceProfileCache {
  /// Creates a cache stored in [file].
  const new(this.file);

  /// The JSON file.
  final File file;

  @override
  Future<DeviceProfile?> read() async {
    try {
      if (!file.existsSync()) return null;
      final json = jsonDecode(await file.readAsString());
      return DeviceProfile.fromJson(json as Map<String, dynamic>);
    } on Object {
      // Unreadable or from an incompatible version: start over.
      if (file.existsSync()) await file.delete();
      return null;
    }
  }

  @override
  Future<void> write(DeviceProfile profile) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(profile.toJson()), flush: true);
    await temporary.rename(file.path);
  }
}
