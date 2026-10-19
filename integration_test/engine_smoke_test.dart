import 'dart:io';

import 'package:emberwit/app/app.dart';
import 'package:emberwit/app/debug/engine_debug_controller.dart';
import 'package:emberwit/app/debug/engine_debug_page.dart';
import 'package:emberwit/core/config/flavor_config.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:emberwit/engine/llama/llama_inference_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// On-device proof of the llama.cpp engine.
///
/// Needs a GGUF model in the app's models folder:
///   tool/push_debug_model.sh SmolLM2-135M-Instruct-Q4_K_M.gguf
///   flutter test integration_test/engine_smoke_test.dart --flavor dev
Future<String?> _firstModel() async {
  final dir = Directory(
    '${(await getApplicationSupportDirectory()).path}/models',
  );
  if (!dir.existsSync()) return null;
  final models =
      dir
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.gguf'))
          .toList()
        ..sort();
  return models.isEmpty ? null : models.first;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('engine loads a model and streams a reply', (tester) async {
    final model = await _firstModel();
    if (model == null) {
      markTestSkipped('No model; run tool/push_debug_model.sh first');
      return;
    }
    final engine = LlamaInferenceEngine();
    addTearDown(engine.dispose);

    final loaded = await engine.loadModel(LoadModelRequest(path: model)).last;
    expect(loaded, isA<ModelLoaded>(), reason: '$loaded');
    final info = (loaded as ModelLoaded).info;

    final events = await engine
        .generate(
          const GenerationRequest(
            prompt: ChatPrompt([
              ChatTurn(role: ChatRole.user, content: 'Name three colours.'),
            ]),
            sampling: SamplingSettings(temperature: 0),
            maxTokens: 64,
          ),
        )
        .toList();
    final text = events.whereType<TokenGenerated>().map((e) => e.text).join();
    final stats = (events.last as GenerationCompleted).stats;
    expect(text.trim(), isNotEmpty);

    final report = {
      'model': info.description,
      'devices': info.devices.join(','),
      'threads': info.threads,
      'load_ms': loaded.duration.inMilliseconds,
      'prompt_tokens': stats.promptTokens,
      'generated_tokens': stats.generatedTokens,
      'ttft_ms': stats.timeToFirstToken.inMilliseconds,
      'tokens_per_second': stats.tokensPerSecond.toStringAsFixed(2),
      'prompt_tokens_per_second': stats.promptTokensPerSecond.toStringAsFixed(
        2,
      ),
    };
    binding.reportData = {'engine_benchmark': report};
    // Printed for the phase report; never contains user content.
    // ignore: avoid_print
    print('ENGINE_BENCHMARK $report\nOUTPUT: $text');
  });

  testWidgets('debug screen loads and generates', (tester) async {
    if (await _firstModel() == null) {
      markTestSkipped('No model; run tool/push_debug_model.sh first');
      return;
    }
    // The real app with the real engine. Not main(): bootstrap replaces
    // FlutterError.onError, which would hide failures from the test.
    final container = ProviderContainer(
      overrides: [
        flavorConfigProvider.overrideWithValue(
          FlavorConfig.forFlavor(AppFlavor.dev),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EmberwitApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-engine-debug')));
    await tester.pumpAndSettle();
    expect(find.byType(EngineDebugPage), findsOneWidget);

    EngineDebugState debugState() =>
        container.read(engineDebugControllerProvider);

    await tester.tap(find.text('Load'));
    for (var i = 0; i < 240 && debugState().model == null; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(debugState().model, isNotNull, reason: '${debugState().failure}');

    final generate = find.byKey(const Key('debug-generate'));
    await tester.ensureVisible(generate);
    await tester.pumpAndSettle();
    await tester.tap(generate);
    for (var i = 0; i < 480 && debugState().stats == null; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(debugState().stats, isNotNull, reason: '${debugState().failure}');
    expect(debugState().output.trim(), isNotEmpty);
  });
}
