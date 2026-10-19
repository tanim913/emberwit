import 'package:emberwit/core/device/device_profile.dart';

const int _gib = 1024 * 1024 * 1024;

/// Assigns a [DeviceTier] from RAM, then lowers it when the benchmark shows
/// the device is slower than its RAM suggests.
///
/// Phones report less RAM than advertised (a "4 GB" phone reports about
/// 3.7 GiB), so the thresholds sit between the advertised sizes.
final class DeviceTierClassifier {
  /// Creates a classifier. Defaults were chosen for 2020 to 2026 phones.
  const new({
    this.midRamBytes = (4.5 * _gib) ~/ 1,
    this.highRamBytes = (6.5 * _gib) ~/ 1,
    this.flagshipRamBytes = (10.5 * _gib) ~/ 1,
    this.minimumBandwidth = const {
      DeviceTier.mid: 1.5e9,
      DeviceTier.high: 3e9,
      DeviceTier.flagship: 5e9,
    },
  });

  /// Minimum total RAM for [DeviceTier.mid].
  final int midRamBytes;

  /// Minimum total RAM for [DeviceTier.high].
  final int highRamBytes;

  /// Minimum total RAM for [DeviceTier.flagship].
  final int flagshipRamBytes;

  /// Minimum benchmark bandwidth (bytes/s, see
  /// [BenchmarkResult.effectiveBandwidth]) a tier needs. A device below it is
  /// moved down one tier per miss.
  final Map<DeviceTier, double> minimumBandwidth;

  /// The tier of [profile].
  DeviceTier classify(DeviceProfile profile) {
    var tier = tierForRam(profile.totalRamBytes);
    final bandwidth = profile.benchmark?.effectiveBandwidth;
    if (bandwidth != null) {
      while (tier != DeviceTier.low &&
          bandwidth < (minimumBandwidth[tier] ?? 0)) {
        tier = DeviceTier.values[tier.index - 1];
      }
    }
    return tier;
  }

  /// The tier for [totalRamBytes] alone.
  DeviceTier tierForRam(int totalRamBytes) {
    if (totalRamBytes >= flagshipRamBytes) return DeviceTier.flagship;
    if (totalRamBytes >= highRamBytes) return DeviceTier.high;
    if (totalRamBytes >= midRamBytes) return DeviceTier.mid;
    return DeviceTier.low;
  }
}

/// Default context length (tokens) for chats on a device of [tier].
///
/// Longer contexts cost memory (KV cache) and slow down prompt processing, so
/// low end devices get shorter defaults.
int defaultContextLength(DeviceTier tier) => switch (tier) {
  DeviceTier.low => 1024,
  DeviceTier.mid => 2048,
  DeviceTier.high => 4096,
  DeviceTier.flagship => 8192,
};

/// Normalises raw CPU feature flags from `/proc/cpuinfo` (Android, Linux) or
/// `sysctl` (Apple) to the names the app uses: `dotprod`, `i8mm`, `fp16`,
/// `bf16`, `sve`, `sve2`, `sme`, `avx`, `avx2`, `avx512`, `fma`.
List<String> normalizeCpuFeatures(Iterable<String> raw) {
  const aliases = {
    'asimddp': 'dotprod',
    'dotprod': 'dotprod',
    'feat_dotprod': 'dotprod',
    'i8mm': 'i8mm',
    'feat_i8mm': 'i8mm',
    'asimdhp': 'fp16',
    'fphp': 'fp16',
    'feat_fp16': 'fp16',
    'bf16': 'bf16',
    'feat_bf16': 'bf16',
    'sve': 'sve',
    'sve2': 'sve2',
    'sme': 'sme',
    'feat_sme': 'sme',
    'avx': 'avx',
    'avx2': 'avx2',
    'avx512f': 'avx512',
    'fma': 'fma',
  };
  final features = <String>{};
  for (final flag in raw) {
    final name = aliases[flag.trim().toLowerCase()];
    if (name != null) features.add(name);
  }
  return features.toList()..sort();
}
