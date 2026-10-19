import 'package:emberwit/core/device/device_profile.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'device_conditions.g.dart';

/// Conditions that change while the app runs and decide how hard the model
/// may work: heat, battery and memory.
@immutable
final class DeviceConditions {
  /// Creates a reading.
  const new({
    this.thermalState = ThermalState.unknown,
    this.batteryLevel,
    this.isCharging,
    this.lowPowerMode = false,
    this.availableRamBytes,
  });

  /// Thermal pressure reported by the OS.
  final ThermalState thermalState;

  /// Battery charge 0 to 100, `null` when unknown.
  final int? batteryLevel;

  /// Whether the device is charging, `null` when unknown.
  final bool? isCharging;

  /// Battery saver (Android) or Low Power Mode (iOS).
  final bool lowPowerMode;

  /// RAM currently available, `null` when unknown.
  final int? availableRamBytes;

  @override
  bool operator ==(Object other) =>
      other is DeviceConditions &&
      other.thermalState == thermalState &&
      other.batteryLevel == batteryLevel &&
      other.isCharging == isCharging &&
      other.lowPowerMode == lowPowerMode &&
      other.availableRamBytes == availableRamBytes;

  @override
  int get hashCode => Object.hash(
    thermalState,
    batteryLevel,
    isCharging,
    lowPowerMode,
    availableRamBytes,
  );
}

/// Reads [DeviceConditions]. Implemented by the device_profiler feature and
/// wired in `featureBindings()`.
abstract interface class DeviceConditionsSource {
  /// A fresh reading. Throws on platform errors.
  Future<DeviceConditions> read();
}

/// The conditions source. Overridden by `featureBindings()`.
@Riverpod(keepAlive: true)
DeviceConditionsSource deviceConditionsSource(Ref ref) => throw StateError(
  'deviceConditionsSourceProvider must be overridden by featureBindings().',
);
