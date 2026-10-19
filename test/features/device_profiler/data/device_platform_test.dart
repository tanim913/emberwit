import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/utils/clock.dart';
import 'package:emberwit/features/device_profiler/data/benchmark_model_source.dart';
import 'package:emberwit/features/device_profiler/data/device_platform_channel.dart';
import 'package:emberwit/features/device_profiler/data/device_snapshot_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBattery extends Mock implements Battery;

const _channel = MethodChannel('app.emberwit/device_profiler');

const _snapshotMap = <String, Object?>{
  'totalRamBytes': 8000000000,
  'availableRamBytes': 3000000000,
  'lowMemory': false,
  'freeStorageBytes': 20000000000,
  'totalStorageBytes': 128000000000,
  'thermalState': 'serious',
  'lowPowerMode': true,
  'cpuCores': 8,
  'performanceCores': 4,
  'cpuFlags': ['fp', 'asimd', 'asimddp', 'i8mm', 'asimdhp'],
  'gpuBackends': ['vulkan'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockChannel(Future<Object?>? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(_channel, handler);
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  }

  group('NativeDeviceSnapshot.fromMap', () {
    test('reads every field', () {
      final s = NativeDeviceSnapshot.fromMap(_snapshotMap);
      expect(s.totalRamBytes, 8000000000);
      expect(s.availableRamBytes, 3000000000);
      expect(s.freeStorageBytes, 20000000000);
      expect(s.totalStorageBytes, 128000000000);
      expect(s.thermalState, 'serious');
      expect(s.lowPowerMode, isTrue);
      expect(s.cpuCores, 8);
      expect(s.performanceCores, 4);
      expect(s.cpuFlags, contains('asimddp'));
      expect(s.gpuBackends, ['vulkan']);
    });

    test('uses safe defaults for missing or mistyped values', () {
      final s = NativeDeviceSnapshot.fromMap(const {
        'cpuFlags': [1, 'sve'],
        'totalRamBytes': 1.5e9,
      });
      expect(s.totalRamBytes, 1500000000);
      expect(s.availableRamBytes, 0);
      expect(s.thermalState, 'unknown');
      expect(s.lowPowerMode, isFalse);
      expect(s.cpuFlags, ['sve']);
      expect(s.gpuBackends, isEmpty);
    });
  });

  test('parseThermalState maps names and falls back to unknown', () {
    expect(parseThermalState('critical'), ThermalState.critical);
    expect(parseThermalState('lava'), ThermalState.unknown);
  });

  group('PlatformDeviceSnapshotSource', () {
    late _MockBattery battery;

    setUp(() {
      battery = _MockBattery();
      when(() => battery.batteryLevel).thenAnswer((_) async => 64);
      when(() => battery.batteryState)
          .thenAnswer((_) async => BatteryState.charging);
      mockChannel((call) async => _snapshotMap);
    });

    test('combines native values, battery and normalised features', () async {
      final source = PlatformDeviceSnapshotSource(
        battery: battery,
        clock: FixedClock(DateTime.utc(2026)),
      );
      final profile = await source.snapshot();
      expect(profile.totalRamBytes, 8000000000);
      expect(profile.cpuFeatures, ['dotprod', 'fp16', 'i8mm']);
      expect(profile.gpuBackends, ['vulkan']);
      expect(profile.thermalState, ThermalState.serious);
      expect(profile.lowPowerMode, isTrue);
      expect(profile.batteryLevel, 64);
      expect(profile.isCharging, isTrue);
      expect(profile.profiledAt, DateTime.utc(2026));
      expect(profile.benchmark, isNull);
      // Tests run on the host, which is neither Android nor iOS.
      expect(profile.platform, DevicePlatform.other);
    });

    test('maps battery states', () async {
      final source = PlatformDeviceSnapshotSource(battery: battery);
      Future<bool?> chargingFor(BatteryState state) async {
        when(() => battery.batteryState).thenAnswer((_) async => state);
        return (await source.snapshot()).isCharging;
      }

      expect(await chargingFor(BatteryState.full), isTrue);
      expect(await chargingFor(BatteryState.discharging), isFalse);
      expect(await chargingFor(BatteryState.connectedNotCharging), isFalse);
      expect(await chargingFor(BatteryState.unknown), isNull);
    });

    test('tolerates devices without a battery', () async {
      when(() => battery.batteryLevel).thenThrow(PlatformException(code: 'x'));
      final profile = await PlatformDeviceSnapshotSource(battery: battery)
          .snapshot();
      expect(profile.batteryLevel, isNull);
      expect(profile.isCharging, isNull);
    });
  });

  group('AssetBenchmarkModelSource', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('bench'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('returns the unpacked model', () async {
      final file = File('${dir.path}/benchmark.gguf')
        ..writeAsBytesSync(List.filled(1000, 1));
      MethodCall? received;
      mockChannel((call) async {
        received = call;
        return file.path;
      });
      final result = await AssetBenchmarkModelSource(cacheDirectory: dir)
          .prepare();
      final model = result.valueOrNull!;
      expect(model.path, file.path);
      expect(model.sizeBytes, 1000);
      expect(model.name, AssetBenchmarkModelSource.modelName);
      expect(received!.method, 'prepareAsset');
      expect(received!.arguments, {
        'asset': 'assets/models/benchmark.gguf',
        'target': '${dir.path}/benchmark.gguf',
      });
    });

    test('reports a build without the benchmark model', () async {
      mockChannel((call) async => null);
      expect(
        (await AssetBenchmarkModelSource(
          cacheDirectory: dir,
        ).prepare()).failureOrNull,
        const BenchmarkUnavailableFailure(),
      );
      mockChannel((call) async => '${dir.path}/missing.gguf');
      expect(
        (await AssetBenchmarkModelSource(
          cacheDirectory: dir,
        ).prepare()).failureOrNull,
        const BenchmarkUnavailableFailure(),
      );
    });

    test('maps native errors', () async {
      mockChannel((call) async => throw PlatformException(code: 'io'));
      expect(
        (await AssetBenchmarkModelSource(
          cacheDirectory: dir,
        ).prepare()).failureOrNull,
        isA<DeviceProfilingFailure>(),
      );
    });
  });
}
