import 'dart:convert';

import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/engine/engine_models.dart';
import 'package:emberwit/engine/llama/cancel_flag.dart';
import 'package:emberwit/engine/llama/llama_protocol.dart';
import 'package:emberwit/engine/llama/llama_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llama_ffi/llama_ffi.dart';

import '../fakes/fake_llama_runtime.dart';

class _Harness {
  new(
    this.runtime, {
    LlamaRuntime Function()? factory,
    MemoryCancelFlag? cancel,
  }) : cancel = cancel ?? MemoryCancelFlag() {
    worker = LlamaWorker(
      runtimeFactory: factory ?? () => runtime,
      cancelFlag: this.cancel,
      emit: events.add,
    );
  }

  final FakeLlamaRuntime runtime;
  final MemoryCancelFlag cancel;
  final events = <WorkerEvent>[];
  late final LlamaWorker worker;

  void load({int batchSize = 512}) => worker.handle(
    LoadCommand(
      1,
      request: LoadModelRequest(
        path: '/models/fake.gguf',
        contextLength: 256,
        batchSize: batchSize,
      ),
      threads: 3,
      gpuLayers: 0,
    ),
  );

  void generate(GenerationRequest request) =>
      worker.handle(GenerateCommand(2, request));

  String get text => events.whereType<TokenEvent>().map((e) => e.text).join();

  GenerationStats get stats =>
      events.whereType<GenerationDoneEvent>().single.stats;

  AppFailure get failure => events.whereType<FailedEvent>().single.failure;
}

const _raw = GenerationRequest(prompt: RawPrompt('Once upon a time'));

void main() {
  group('LlamaWorker load', () {
    test('reports progress, then model info', () {
      final h = _Harness(FakeLlamaRuntime())..load();
      final progress = h.events.whereType<LoadProgressEvent>();
      expect(progress.map((e) => e.fraction), [0.25, 0.5, 1.0]);
      final loaded = h.events.last as LoadedEvent;
      expect(loaded.id, 1);
      expect(loaded.info.architecture, 'llama');
      expect(loaded.info.contextLength, 256);
      expect(loaded.info.threads, 3);
      expect(loaded.info.hasChatTemplate, isTrue);
      expect(loaded.info.devices, ['CPU']);
      expect(h.runtime.contextParams!.threads, 3);
      expect(h.runtime.modelParams!.useMmap, isTrue);
    });

    test('maps runtime errors to load failure reasons', () {
      final h = _Harness(
        FakeLlamaRuntime(loadError: LlamaErrorCode.contextCreationFailed),
      )..load();
      expect(
        h.failure,
        const ModelLoadFailure(ModelLoadFailureReason.insufficientMemory),
      );
    });

    test('cancels through the progress callback', () {
      final h = _Harness(FakeLlamaRuntime());
      h.cancel.set();
      h.load();
      expect(
        h.failure,
        const ModelLoadFailure(ModelLoadFailureReason.cancelled),
      );
    });

    test('reports an unavailable engine when the runtime cannot start', () {
      final h = _Harness(FakeLlamaRuntime(), factory: unavailableRuntime)
        ..load();
      expect(
        h.failure,
        const ModelLoadFailure(ModelLoadFailureReason.engineUnavailable),
      );
    });

    test('maps every error code', () {
      expect(
        {for (final code in LlamaErrorCode.values) loadFailureReason(code)},
        containsAll(<ModelLoadFailureReason>[
          ModelLoadFailureReason.fileNotFound,
          ModelLoadFailureReason.invalidFormat,
          ModelLoadFailureReason.insufficientMemory,
          ModelLoadFailureReason.cancelled,
          ModelLoadFailureReason.engineUnavailable,
          ModelLoadFailureReason.unsupportedModel,
        ]),
      );
    });
  });

  group('LlamaWorker generate', () {
    test('fails without a loaded model', () {
      final h = _Harness(FakeLlamaRuntime())..generate(_raw);
      expect(h.failure, const NoModelLoadedFailure());
    });

    test('streams tokens until end of sequence', () {
      final h = _Harness(FakeLlamaRuntime(script: [5, 6, 7, 0, 8]))
        ..load()
        ..generate(_raw);
      expect(h.text, '5 6 7 ');
      expect(h.stats.stopReason, StopReason.endOfSequence);
      expect(h.stats.generatedTokens, 3);
      expect(h.stats.promptTokens, 4);
      expect(h.stats.totalTokens, 7);
      expect(h.runtime.tokenized, ['Once upon a time']);
      // Prompt, then each token except the last one sampled.
      expect(h.runtime.decodes.first, hasLength(4));
      expect(h.runtime.decodes.skip(1), [
        [5],
        [6],
        [7],
      ]);
    });

    test('stops at maxTokens', () {
      final h = _Harness(FakeLlamaRuntime())
        ..load()
        ..generate(
          const GenerationRequest(prompt: RawPrompt('a'), maxTokens: 3),
        );
      expect(h.text, '1 2 3 ');
      expect(h.stats.stopReason, StopReason.maxTokens);
      expect(h.stats.generatedTokens, 3);
    });

    test('stops at a stop sequence without emitting it', () {
      final h =
          _Harness(
              FakeLlamaRuntime(
                script: [1, 2, 3, 4],
                pieces: {
                  1: utf8.encode('Hello'),
                  2: utf8.encode(' <|'),
                  3: utf8.encode('end|>'),
                  4: utf8.encode('never'),
                },
              ),
            )
            ..load()
            ..generate(
              const GenerationRequest(
                prompt: RawPrompt('a'),
                stopSequences: ['<|end|>'],
              ),
            );
      expect(h.text, 'Hello ');
      expect(h.stats.stopReason, StopReason.stopSequence);
    });

    test('emits whole Bengali characters when tokens split bytes', () {
      final bytes = utf8.encode('আমি');
      final h =
          _Harness(
              FakeLlamaRuntime(
                script: [1, 2, 3],
                pieces: {
                  1: bytes.sublist(0, 2),
                  2: bytes.sublist(2, 5),
                  3: bytes.sublist(5),
                },
              ),
            )
            ..load()
            ..generate(_raw);
      final pieces = h.events.whereType<TokenEvent>().map((e) => e.text);
      expect(pieces.every((p) => !p.contains('�')), isTrue);
      expect(h.text, 'আমি');
    });

    test('flushes held back text when generation ends normally', () {
      final h =
          _Harness(
              FakeLlamaRuntime(script: [1], pieces: {1: utf8.encode('ok <|')}),
            )
            ..load()
            ..generate(
              const GenerationRequest(
                prompt: RawPrompt('a'),
                stopSequences: ['<|end|>'],
              ),
            );
      expect(h.text, 'ok <|');
    });

    test('stops when cancelled mid generation', () {
      final cancel = MemoryCancelFlag();
      final h =
          _Harness(
              FakeLlamaRuntime(
                onSample: (n) {
                  if (n == 2) cancel.set();
                },
              ),
              cancel: cancel,
            )
            ..load()
            ..generate(_raw);
      expect(h.stats.stopReason, StopReason.cancelled);
      expect(h.stats.generatedTokens, 2);
    });

    test('stops before prefill when already cancelled', () {
      final h = _Harness(FakeLlamaRuntime())..load();
      h.cancel.set();
      h.generate(_raw);
      expect(h.stats.stopReason, StopReason.cancelled);
      expect(h.stats.generatedTokens, 0);
      expect(h.runtime.decodes, isEmpty);
    });

    test('evaluates long prompts in batch sized chunks', () {
      final h = _Harness(FakeLlamaRuntime(promptTokenCount: 10, script: [0]))
        ..load(batchSize: 4)
        ..generate(_raw);
      expect(h.runtime.decodes.map((d) => d.length), [4, 4, 2]);
    });

    test('rejects prompts that do not fit in the context', () {
      final h = _Harness(FakeLlamaRuntime(promptTokenCount: 256))
        ..load()
        ..generate(_raw);
      expect(
        h.failure,
        const ContextOverflowFailure(promptTokens: 256, contextLength: 256),
      );
    });

    test('stops when the context fills up', () {
      final h =
          _Harness(
              FakeLlamaRuntime(
                promptTokenCount: 250,
                script: List.generate(20, (i) => i + 1),
              ),
            )
            ..load()
            ..generate(_raw);
      expect(h.stats.stopReason, StopReason.contextFull);
      // 250 prompt + 6 evaluated tokens fill 256; the 7th is sampled from
      // the full context and emitted, but never evaluated.
      expect(h.stats.generatedTokens, 7);
      expect(h.runtime.usedContext, 256);
    });

    test('treats a context full decode error as a normal stop', () {
      final h =
          _Harness(
              FakeLlamaRuntime(
                decodeError: LlamaErrorCode.contextFull,
                decodeErrorAfter: 2,
              ),
            )
            ..load()
            ..generate(_raw);
      expect(h.stats.stopReason, StopReason.contextFull);
    });

    test('fails on a decode error', () {
      final h =
          _Harness(FakeLlamaRuntime(decodeError: LlamaErrorCode.decodeFailed))
            ..load()
            ..generate(_raw);
      expect(h.failure, isA<GenerationFailure>());
      expect(h.events.whereType<GenerationDoneEvent>(), isEmpty);
    });

    test('formats chat prompts with the model template', () {
      final h = _Harness(FakeLlamaRuntime(script: [0]))
        ..load()
        ..generate(
          const GenerationRequest(
            prompt: ChatPrompt([
              ChatTurn(role: ChatRole.system, content: 'Be brief.'),
              ChatTurn(role: ChatRole.user, content: 'Hi'),
            ]),
          ),
        );
      final messages = h.runtime.templated.single;
      expect(messages.map((m) => m.role), ['system', 'user']);
      expect(h.runtime.tokenized.single, 'system: Be brief. user: Hi');
    });

    test('fails when the model has no usable chat template', () {
      final h = _Harness(FakeLlamaRuntime(templateError: true))
        ..load()
        ..generate(
          const GenerationRequest(
            prompt: ChatPrompt([ChatTurn(role: ChatRole.user, content: 'x')]),
          ),
        );
      expect(h.failure, const GenerationFailure('chat template unavailable'));
    });

    test('passes sampling settings to the runtime', () {
      final h = _Harness(FakeLlamaRuntime(script: [0]))
        ..load()
        ..generate(
          const GenerationRequest(
            prompt: RawPrompt('a'),
            sampling: SamplingSettings(temperature: 0.2, topP: 0.8, seed: 7),
          ),
        );
      final params = h.runtime.samplerParams!;
      expect(params.temperature, 0.2);
      expect(params.topP, 0.8);
      expect(params.seed, 7);
      expect(samplerParams(const SamplingSettings()).seed, 0xFFFFFFFF);
    });
  });

  group('LlamaWorker lifecycle', () {
    test('unload frees the model', () {
      final h = _Harness(FakeLlamaRuntime())..load();
      expect(h.worker.handle(const UnloadCommand(3)), isTrue);
      expect(h.events.last, isA<DoneEvent>());
      expect(h.runtime.isLoaded, isFalse);
      h.generate(_raw);
      expect(h.failure, const NoModelLoadedFailure());
    });

    test('shutdown disposes the runtime and stops the loop', () {
      final h = _Harness(FakeLlamaRuntime())..load();
      expect(h.worker.handle(const ShutdownCommand(4)), isFalse);
      expect(h.runtime.disposed, isTrue);
      expect((h.events.last as DoneEvent).id, 4);
    });
  });
}
