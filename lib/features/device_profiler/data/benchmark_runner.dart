import 'dart:async';

import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/core/utils/clock.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:emberwit/features/device_profiler/data/benchmark_model_source.dart';

/// Fixed English prompt for the benchmark. Short, so the run measures
/// generation speed rather than prompt processing.
const String benchmarkPrompt =
    'Once upon a time, in a small village by the river, there lived a '
    'curious girl who loved to';

/// Runs the micro benchmark on an [InferenceEngine].
///
/// Loads the benchmark model with a small context, generates greedily for at
/// most [maxTokens] tokens or until the [timeBudget] (load included) runs
/// out, then unloads the model. The engine is left idle.
final class BenchmarkRunner {
  /// Creates a runner.
  const new({
    required this.engine,
    this.clock = const SystemClock(),
    this.timeBudget = const Duration(seconds: 10),
    this.maxTokens = 128,
    this.minimumTokens = 8,
  });

  /// Engine to measure.
  final InferenceEngine engine;

  /// Timestamp source.
  final Clock clock;

  /// Total time allowed, including model load.
  final Duration timeBudget;

  /// Upper bound on generated tokens.
  final int maxTokens;

  /// Fewer generated tokens than this is not a meaningful measurement.
  final int minimumTokens;

  /// Runs the benchmark with [model] on [threads] CPU threads, reporting
  /// progress to [onProgress].
  Future<Result<BenchmarkResult>> run(
    BenchmarkModelFile model, {
    required int threads,
    required void Function(BenchmarkStage stage, double fraction) onProgress,
  }) async {
    if (engine.state == EngineState.loading ||
        engine.state == EngineState.generating) {
      return const Err(EngineBusyFailure());
    }
    final watch = Stopwatch()..start();
    try {
      onProgress(BenchmarkStage.loading, 0.1);
      ModelLoaded? loaded;
      AppFailure? loadFailure;
      await for (final event in engine.loadModel(
        LoadModelRequest(
          path: model.path,
          contextLength: 512,
          batchSize: 256,
          threads: threads,
        ),
      )) {
        switch (event) {
          case ModelLoadProgress(:final fraction):
            onProgress(BenchmarkStage.loading, 0.1 + 0.3 * fraction);
          case ModelLoaded():
            loaded = event;
          case ModelLoadFailed(:final failure):
            loadFailure = failure;
        }
      }
      if (loaded == null) {
        return Err(loadFailure ?? const UnexpectedFailure());
      }

      final remaining = timeBudget - watch.elapsed;
      final budget = remaining < const Duration(seconds: 3)
          ? const Duration(seconds: 3)
          : remaining;
      final timer = Timer(budget, () => unawaited(engine.cancel()));
      onProgress(BenchmarkStage.running, 0.4);
      GenerationStats? stats;
      AppFailure? generationFailure;
      var generated = 0;
      try {
        await for (final event in engine.generate(
          GenerationRequest(
            prompt: const RawPrompt(benchmarkPrompt),
            sampling: const SamplingSettings(temperature: 0),
            maxTokens: maxTokens,
          ),
        )) {
          switch (event) {
            case TokenGenerated():
              generated++;
              onProgress(
                BenchmarkStage.running,
                0.4 + 0.6 * (generated / maxTokens).clamp(0, 1),
              );
            case GenerationCompleted():
              stats = event.stats;
            case GenerationFailed(:final failure):
              generationFailure = failure;
          }
        }
      } finally {
        timer.cancel();
      }
      final result = stats;
      if (result == null) {
        return Err(generationFailure ?? const UnexpectedFailure());
      }
      if (result.generatedTokens < minimumTokens) {
        return const Err(
          GenerationFailure('benchmark generated too few tokens'),
        );
      }
      onProgress(BenchmarkStage.running, 1);
      return Ok(
        BenchmarkResult(
          modelName: model.name,
          modelSizeBytes: model.sizeBytes,
          tokensPerSecond: result.tokensPerSecond,
          promptTokensPerSecond: result.promptTokensPerSecond,
          timeToFirstTokenMs: result.timeToFirstToken.inMilliseconds,
          loadTimeMs: loaded.duration.inMilliseconds,
          generatedTokens: result.generatedTokens,
          threads: loaded.info.threads,
          measuredAt: clock.now(),
        ),
      );
    } finally {
      await engine.unloadModel();
    }
  }
}
