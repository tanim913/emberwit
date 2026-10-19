import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/device/device_tier_classifier.dart';
import 'package:emberwit/core/utils/clock.dart';
import 'package:emberwit/features/device_profiler/data/device_platform_channel.dart';

/// Reads a fresh [DeviceProfile] (without benchmark) from the platform.
abstract interface class DeviceSnapshotSource {
  /// Current device facts. Throws on platform errors.
  Future<DeviceProfile> snapshot();
}

/// [DeviceSnapshotSource] for Android and iOS: the native channel for live
/// memory, storage, thermal and CPU facts, device_info_plus for the device
/// and OS, battery_plus for the battery.
final class PlatformDeviceSnapshotSource implements DeviceSnapshotSource {
  /// Creates the source.
  new({
    this._channel = const DevicePlatformChannel(),
    DeviceInfoPlugin? deviceInfo,
    Battery? battery,
    this._clock = const SystemClock(),
  }) : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
       _battery = battery ?? Battery();

  final DevicePlatformChannel _channel;
  final DeviceInfoPlugin _deviceInfo;
  final Battery _battery;
  final Clock _clock;

  @override
  Future<DeviceProfile> snapshot() async {
    final native = await _channel.snapshot();
    final identity = await _identity();
    final battery = await _batteryState();
    return DeviceProfile(
      platform: identity.platform,
      osVersion: identity.osVersion,
      deviceModel: identity.model,
      manufacturer: identity.manufacturer,
      isPhysicalDevice: identity.isPhysical,
      totalRamBytes: native.totalRamBytes,
      availableRamBytes: native.availableRamBytes,
      freeStorageBytes: native.freeStorageBytes,
      totalStorageBytes: native.totalStorageBytes,
      cpuArchitecture: identity.architecture,
      cpuCores: native.cpuCores,
      performanceCores: native.performanceCores,
      cpuFeatures: normalizeCpuFeatures(native.cpuFlags),
      gpuBackends: native.gpuBackends,
      thermalState: parseThermalState(native.thermalState),
      batteryLevel: battery.level,
      isCharging: battery.charging,
      lowPowerMode: native.lowPowerMode,
      profiledAt: _clock.now(),
    );
  }

  Future<_Identity> _identity() async {
    if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      return _Identity(
        platform: DevicePlatform.android,
        osVersion: info.version.release,
        model: info.model,
        manufacturer: info.manufacturer,
        isPhysical: info.isPhysicalDevice,
        architecture: info.supported64BitAbis.isNotEmpty
            ? info.supported64BitAbis.first
            : (info.supportedAbis.isNotEmpty ? info.supportedAbis.first : ''),
      );
    }
    if (Platform.isIOS) {
      final info = await _deviceInfo.iosInfo;
      return _Identity(
        platform: DevicePlatform.ios,
        osVersion: info.systemVersion,
        model: info.utsname.machine,
        manufacturer: 'Apple',
        isPhysical: info.isPhysicalDevice,
        architecture: 'arm64',
      );
    }
    return _Identity(
      platform: DevicePlatform.other,
      osVersion: Platform.operatingSystemVersion,
      model: Platform.localHostname,
      manufacturer: '',
      isPhysical: true,
      architecture: '',
    );
  }

  Future<({int? level, bool? charging})> _batteryState() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      return (
        level: level,
        charging: switch (state) {
          BatteryState.charging || BatteryState.full => true,
          BatteryState.discharging ||
          BatteryState.connectedNotCharging => false,
          BatteryState.unknown => null,
        },
      );
    } on Object {
      // Some emulators and tablets have no battery.
      return (level: null, charging: null);
    }
  }
}

/// Maps the channel's thermal state name to [ThermalState].
ThermalState parseThermalState(String name) => ThermalState.values.firstWhere(
  (s) => s.name == name,
  orElse: () => ThermalState.unknown,
);

final class _Identity {
  const new({
    required this.platform,
    required this.osVersion,
    required this.model,
    required this.manufacturer,
    required this.isPhysical,
    required this.architecture,
  });

  final DevicePlatform platform;
  final String osVersion;
  final String model;
  final String manufacturer;
  final bool isPhysical;
  final String architecture;
}
