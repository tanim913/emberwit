import 'dart:io';

import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/features/device_profiler/data/device_platform_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The model file used by the micro benchmark.
@immutable
final class BenchmarkModelFile {
  /// Creates a description of a ready-to-load benchmark model.
  const new({required this.path, required this.name, required this.sizeBytes});

  /// Absolute path the engine can open.
  final String path;

  /// Model name for reports.
  final String name;

  /// File size in bytes.
  final int sizeBytes;
}

/// Provides the benchmark model as a file on disk.
abstract interface class BenchmarkModelSource {
  /// Makes the model available. Fails with [BenchmarkUnavailableFailure]
  /// when this build does not bundle it.
  Future<Result<BenchmarkModelFile>> prepare();
}

/// [BenchmarkModelSource] for the model bundled as a Flutter asset
/// (`assets/models/benchmark.gguf`, fetched at build time by
/// `tool/fetch_benchmark_model.sh`).
///
/// Android keeps assets inside the APK, so the file is streamed out once to
/// [cacheDirectory] by native code, never through Dart memory. iOS assets
/// are already plain files.
final class AssetBenchmarkModelSource implements BenchmarkModelSource {
  /// Creates the source.
  const new({
    required this.cacheDirectory,
    this._channel = const DevicePlatformChannel(),
  });

  /// Flutter asset key of the bundled model.
  static const String asset = 'assets/models/benchmark.gguf';

  /// Name of the bundled model.
  static const String modelName = 'SmolLM2-135M-Instruct-Q4_0';

  /// Where Android unpacks the model.
  final Directory cacheDirectory;

  final DevicePlatformChannel _channel;

  @override
  Future<Result<BenchmarkModelFile>> prepare() async {
    try {
      final target = '${cacheDirectory.path}/benchmark.gguf';
      final path = await _channel.prepareAsset(asset, target);
      if (path == null) return const Err(BenchmarkUnavailableFailure());
      final file = File(path);
      if (!file.existsSync()) return const Err(BenchmarkUnavailableFailure());
      return Ok(
        BenchmarkModelFile(
          path: path,
          name: modelName,
          sizeBytes: file.lengthSync(),
        ),
      );
    } on PlatformException catch (error, stackTrace) {
      return Err(
        DeviceProfilingFailure(
          'benchmark model unpack failed',
          cause: error.code,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
