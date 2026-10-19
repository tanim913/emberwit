import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/device/device_tier_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/device_fixtures.dart';

void main() {
  const classifier = DeviceTierClassifier();

  group('DeviceTierClassifier', () {
    test('classifies by reported RAM', () {
      // Reported sizes of 3, 4, 6, 8, 12 and 16 GB phones.
      expect(classifier.tierForRam((2.8 * gib).round()), DeviceTier.low);
      expect(classifier.tierForRam((3.7 * gib).round()), DeviceTier.low);
      expect(classifier.tierForRam((5.6 * gib).round()), DeviceTier.mid);
      expect(classifier.tierForRam((7.5 * gib).round()), DeviceTier.high);
      expect(classifier.tierForRam((11.2 * gib).round()), DeviceTier.flagship);
      expect(classifier.tierForRam(15 * gib), DeviceTier.flagship);
    });

    test('uses exact boundaries', () {
      expect(classifier.tierForRam(classifier.midRamBytes - 1), DeviceTier.low);
      expect(classifier.tierForRam(classifier.midRamBytes), DeviceTier.mid);
      expect(classifier.tierForRam(classifier.highRamBytes), DeviceTier.high);
      expect(
        classifier.tierForRam(classifier.flagshipRamBytes),
        DeviceTier.flagship,
      );
    });

    test('keeps the RAM tier when the benchmark is fast enough', () {
      final fast = profile(totalRamBytes: 12 * gib, benchmark: benchmarkAt(90));
      expect(classifier.classify(fast), DeviceTier.flagship);
    });

    test('downgrades slow devices, one tier per missed threshold', () {
      // 92 MB * 40 tok/s = 3.7 GB/s: below flagship (5), above high (3).
      final slow = profile(totalRamBytes: 12 * gib, benchmark: benchmarkAt(40));
      expect(classifier.classify(slow), DeviceTier.high);
      // 92 MB * 10 tok/s = 0.9 GB/s: below every threshold.
      final verySlow = profile(
        totalRamBytes: 12 * gib,
        benchmark: benchmarkAt(10),
      );
      expect(classifier.classify(verySlow), DeviceTier.low);
    });

    test('never goes below low', () {
      final tiny = profile(totalRamBytes: 3 * gib, benchmark: benchmarkAt(1));
      expect(classifier.classify(tiny), DeviceTier.low);
    });

    test('uses RAM alone without a benchmark', () {
      expect(
        classifier.classify(profile(totalRamBytes: 6 * gib)),
        DeviceTier.mid,
      );
    });
  });

  test('default context grows with the tier', () {
    expect(DeviceTier.values.map(defaultContextLength), [
      1024,
      2048,
      4096,
      8192,
    ]);
  });

  group('normalizeCpuFeatures', () {
    test('maps Android /proc/cpuinfo flags', () {
      expect(
        normalizeCpuFeatures(
          'fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp '
                  'cpuid asimdrdm lrcpc dcpop asimddp i8mm bf16 sve sve2'
              .split(' '),
        ),
        ['bf16', 'dotprod', 'fp16', 'i8mm', 'sve', 'sve2'],
      );
    });

    test('maps Apple sysctl names and x86 flags', () {
      expect(normalizeCpuFeatures(['FEAT_DotProd', 'FEAT_I8MM']), [
        'dotprod',
        'i8mm',
      ]);
      expect(
        normalizeCpuFeatures(['sse4_2', 'avx', 'avx2', 'fma', 'avx512f']),
        ['avx', 'avx2', 'avx512', 'fma'],
      );
    });

    test('ignores unknown flags and duplicates', () {
      expect(normalizeCpuFeatures(['asimd', 'asimddp', 'dotprod', ' ']), [
        'dotprod',
      ]);
      expect(normalizeCpuFeatures(const []), isEmpty);
    });
  });

  group('DeviceProfile', () {
    test('round trips through JSON and ignores unknown fields', () {
      final original = profile(benchmark: benchmarkAt(50));
      final json = original.toJson()..['futureField'] = 'x';
      final restored = DeviceProfile.fromJson(
        Map<String, dynamic>.from(
          // Simulate a file round trip: nested objects become maps.
          json..['benchmark'] = original.benchmark!.toJson(),
        ),
      );
      expect(restored, original);
    });

    test('derives CPU capabilities and thread count', () {
      final p = profile(
        cpuFeatures: const ['dotprod', 'i8mm'],
        performanceCores: 6,
      );
      expect(p.hasDotProd, isTrue);
      expect(p.hasI8mm, isTrue);
      expect(p.recommendedThreads, 4);
      expect(profile(performanceCores: 0).recommendedThreads, 1);
      expect(profile(cpuFeatures: const []).hasDotProd, isFalse);
    });

    test('benchmark bandwidth is speed times size', () {
      expect(benchmarkAt(10).effectiveBandwidth, 918930880);
    });
  });
}
