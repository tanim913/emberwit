import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Raw values from the native device profiler channel
/// (`DeviceProfilerChannel.kt` / `DeviceProfilerChannel.swift`).
@immutable
final class NativeDeviceSnapshot {
  /// Creates a snapshot.
  const new({
    required this.totalRamBytes,
    required this.availableRamBytes,
    required this.freeStorageBytes,
    required this.totalStorageBytes,
    required this.thermalState,
    required this.lowPowerMode,
    required this.cpuCores,
    required this.performanceCores,
    required this.cpuFlags,
    required this.gpuBackends,
  });

  /// Parses the channel's map. Missing or mistyped values become safe
  /// defaults, so an older native side never crashes the app.
  factory fromMap(Map<Object?, Object?> map) {
    int integer(String key) => (map[key] as num?)?.toInt() ?? 0;
    List<String> strings(String key) =>
        (map[key] as List<Object?>?)?.whereType<String>().toList() ?? const [];
    return NativeDeviceSnapshot(
      totalRamBytes: integer('totalRamBytes'),
      availableRamBytes: integer('availableRamBytes'),
      freeStorageBytes: integer('freeStorageBytes'),
      totalStorageBytes: integer('totalStorageBytes'),
      thermalState: map['thermalState'] as String? ?? 'unknown',
      lowPowerMode: map['lowPowerMode'] as bool? ?? false,
      cpuCores: integer('cpuCores'),
      performanceCores: integer('performanceCores'),
      cpuFlags: strings('cpuFlags'),
      gpuBackends: strings('gpuBackends'),
    );
  }

  /// Total RAM in bytes.
  final int totalRamBytes;

  /// Available RAM in bytes (on iOS: what this app may still allocate).
  final int availableRamBytes;

  /// Free storage in bytes.
  final int freeStorageBytes;

  /// Storage volume size in bytes.
  final int totalStorageBytes;

  /// `nominal`, `fair`, `serious`, `critical` or `unknown`.
  final String thermalState;

  /// Battery saver / low power mode.
  final bool lowPowerMode;

  /// Logical cores.
  final int cpuCores;

  /// Cores in the fastest clusters.
  final int performanceCores;

  /// Raw CPU feature flags.
  final List<String> cpuFlags;

  /// GPU compute APIs.
  final List<String> gpuBackends;
}

/// Dart side of the native device profiler channel.
class DevicePlatformChannel {
  /// Creates the channel wrapper.
  const new([
    this._channel = const MethodChannel('app.emberwit/device_profiler'),
  ]);

  final MethodChannel _channel;

  /// Reads live device values. Throws [PlatformException] on native errors.
  Future<NativeDeviceSnapshot> snapshot() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('getSnapshot');
    return NativeDeviceSnapshot.fromMap(map ?? const {});
  }

  /// Makes the Flutter [asset] available as a file and returns its path, or
  /// `null` when the asset is not bundled. Android copies it to [target]
  /// (once); iOS returns the path inside the app bundle.
  Future<String?> prepareAsset(String asset, String target) => _channel
      .invokeMethod<String>('prepareAsset', {'asset': asset, 'target': target});
}
