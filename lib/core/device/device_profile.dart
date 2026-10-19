import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_profile.freezed.dart';
part 'device_profile.g.dart';

/// Operating system family.
enum DevicePlatform {
  /// Android.
  android,

  /// iOS.
  ios,

  /// Anything else (desktop, tests).
  other,
}

/// Thermal pressure reported by the operating system.
enum ThermalState {
  /// No throttling.
  nominal,

  /// Slightly elevated; performance mostly unaffected.
  fair,

  /// Throttling likely; heavy work should be reduced.
  serious,

  /// Severe throttling; stop heavy work.
  critical,

  /// Not reported by this OS version.
  unknown,
}

/// Performance class of a device for running language models.
enum DeviceTier {
  /// 3 to 4 GB RAM or a slow CPU. Sub 1B models only.
  low,

  /// About 6 GB RAM. Up to about 2B parameters.
  mid,

  /// About 8 GB RAM. Up to about 4B parameters.
  high,

  /// 12 GB RAM or more with a fast CPU or GPU.
  flagship,
}

/// Measured inference speed from the on-device micro benchmark.
@freezed
abstract class BenchmarkResult with _$BenchmarkResult {
  /// Creates a result.
  const factory({
    /// Name of the benchmark model.
    required String modelName,

    /// Size of the benchmark model file in bytes.
    required int modelSizeBytes,

    /// Generation speed after the first token.
    required double tokensPerSecond,

    /// Prompt processing speed.
    required double promptTokensPerSecond,

    /// Time to first token in milliseconds.
    required int timeToFirstTokenMs,

    /// Model load time in milliseconds.
    required int loadTimeMs,

    /// Tokens generated during the run.
    required int generatedTokens,

    /// CPU threads used.
    required int threads,

    /// When the benchmark ran.
    required DateTime measuredAt,
  }) = _BenchmarkResult;

  /// Restores a result from JSON.
  factory fromJson(Map<String, dynamic> json) =>
      _$BenchmarkResultFromJson(json);

  const new _();

  /// Effective memory bandwidth in bytes per second: every generated token
  /// reads (roughly) all weights once, so speed times size approximates how
  /// fast this device streams weights.
  double get effectiveBandwidth => tokensPerSecond * modelSizeBytes;
}

/// Everything the app knows about the device's ability to run models.
@freezed
abstract class DeviceProfile with _$DeviceProfile {
  /// Creates a profile.
  const factory({
    required DevicePlatform platform,

    /// OS version, for example `14` or `17.5`.
    required String osVersion,

    /// Device model, for example `Pixel 8` or `iPhone15,3`.
    required String deviceModel,

    /// Manufacturer, for example `Google` or `Apple`.
    required String manufacturer,

    /// `false` on emulators and simulators.
    required bool isPhysicalDevice,

    /// Total RAM in bytes.
    required int totalRamBytes,

    /// RAM currently available to apps (on iOS: to this app) in bytes.
    required int availableRamBytes,

    /// Free space on the app's storage volume in bytes.
    required int freeStorageBytes,

    /// Size of the app's storage volume in bytes.
    required int totalStorageBytes,

    /// Primary CPU architecture, for example `arm64-v8a` or `arm64`.
    required String cpuArchitecture,

    /// Logical CPU cores.
    required int cpuCores,

    /// Cores in the fastest clusters (performance cores).
    required int performanceCores,

    /// Normalised CPU features, for example `dotprod`, `i8mm`, `fp16`.
    required List<String> cpuFeatures,

    /// GPU compute APIs present, for example `metal` or `vulkan`.
    required List<String> gpuBackends,

    /// Thermal pressure when profiled.
    required ThermalState thermalState,

    /// When the profile was taken.
    required DateTime profiledAt,

    /// Battery charge 0 to 100, or `null` when unknown.
    int? batteryLevel,

    /// Whether the device is charging, or `null` when unknown.
    bool? isCharging,

    /// Whether battery saver / low power mode is on.
    @Default(false) bool lowPowerMode,

    /// Latest micro benchmark, if one ran.
    BenchmarkResult? benchmark,
  }) = _DeviceProfile;

  /// Restores a profile from JSON. Unknown fields are ignored.
  factory fromJson(Map<String, dynamic> json) => _$DeviceProfileFromJson(json);

  const new _();

  /// CPU supports the ARM dot product instructions (big speedup for
  /// quantized models).
  bool get hasDotProd => cpuFeatures.contains('dotprod');

  /// CPU supports the ARM int8 matrix multiply instructions.
  bool get hasI8mm => cpuFeatures.contains('i8mm');

  /// Threads to use for inference: the performance cores, at most four.
  int get recommendedThreads => performanceCores.clamp(1, 4);
}
