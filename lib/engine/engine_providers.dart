import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:emberwit/engine/llama/llama_inference_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'engine_providers.g.dart';

/// The app's single inference engine.
///
/// Kept alive for the app lifetime so the loaded model survives navigation.
/// Swap the implementation here, or override the provider in tests.
@Riverpod(keepAlive: true)
InferenceEngine inferenceEngine(Ref ref) {
  final engine = LlamaInferenceEngine(logger: ref.watch(appLoggerProvider));
  ref.onDispose(engine.dispose);
  return engine;
}
