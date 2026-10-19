import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/runtime/runtime_policy.dart';
import 'package:emberwit/core/utils/clock.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:emberwit/features/chat/data/chat_database.dart';
import 'package:emberwit/features/chat/data/chat_repository_impl.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:emberwit/features/chat/domain/chat_responder.dart';
import 'package:emberwit/features/chat/domain/device_actions.dart';
import 'package:emberwit/features/chat/domain/reply_language.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/catalog_fixtures.dart';
import '../../../helpers/chat_db.dart';
import '../../../helpers/fake_device_actions.dart';
import '../../../helpers/fake_inference_engine.dart';
import '../../model_manager/fakes.dart';

InstalledModel installed(String id, {String template = 'chatml'}) {
  final base = entry(id: id);
  return InstalledModel(
    id: id,
    displayName: id,
    fileName: '$id.gguf',
    sizeBytes: 1,
    sha256: 'a' * 64,
    verification: ModelVerification.verified,
    catalogEntry: CatalogEntry.fromJson(
      base.toJson()..['chatTemplate'] = template,
    ),
    installedAt: DateTime.utc(2026),
  );
}

void main() {
  late ChatDatabase db;
  late ChatRepositoryImpl repo;
  late FakeInferenceEngine engine;
  late FakeModelLibrary library;
  late ChatResponder responder;

  setUp(() {
    db = memoryChatDatabase();
    repo = ChatRepositoryImpl(db, clock: FixedClock(DateTime.utc(2026)));
    engine = FakeInferenceEngine(tokens: ['Hello', ' there', '!']);
    library = FakeModelLibrary(
      LibraryState(installed: [installed('llama-q4', template: 'llama3')]),
    );
    responder = ChatResponder(
      engine: engine,
      models: library,
      repository: repo,
      threads: () => 3,
    );
  });
  tearDown(() => db.close());

  Future<List<ReplyEvent>> send(Conversation c, String text) => responder
      .send(conversation: c, text: text, untitled: 'New chat')
      .toList();

  test('loads the model, streams the reply and saves it with stats', () async {
    final chat = await repo.createConversation(
      title: 'New chat',
      settings: const ConversationSettings(
        systemPrompt: 'Be kind.',
        temperature: 0.3,
      ),
    );
    final events = await send(chat, '  How are you?  ');

    expect(events.whereType<ReplyLoadingModel>(), isNotEmpty);
    expect(events.whereType<ReplyStarted>().single.droppedMessages, 0);
    expect(events.whereType<ReplyText>().last.content, 'Hello there!');
    final finished = events.last as ReplyFinished;
    expect(finished.message.status, MessageStatus.complete);
    expect(finished.message.stats!.generatedTokens, 3);
    expect(finished.message.modelId, 'llama-q4');

    final load = engine.loadRequests.single;
    expect(load.path, '/models/llama-q4.gguf');
    expect(load.contextLength, 2048);
    expect(load.threads, 3);

    final request = engine.requests.single;
    final prompt = (request.prompt as RawPrompt).text;
    expect(prompt, startsWith('<|start_header_id|>system<|end_header_id|>'));
    expect(prompt, contains('How are you?<|eot_id|>'));
    expect(request.stopSequences, contains('<|eot_id|>'));
    expect(request.sampling.temperature, 0.3);

    final saved = await repo.messages(chat.id);
    expect(saved.map((m) => m.content), ['How are you?', 'Hello there!']);
    final renamed = await repo.watchConversation(chat.id).first;
    expect(renamed!.title, 'How are you?');
  });

  test('reuses a loaded model and sends the history', () async {
    final chat = await repo.createConversation(title: 'Kept');
    await send(chat, 'First');
    await send(chat, 'Second');
    expect(engine.loadRequests, hasLength(1));
    final prompt = (engine.requests.last.prompt as RawPrompt).text;
    expect(prompt, contains('First'));
    expect(prompt, contains('Hello there!'));
    expect(prompt, contains('Second'));
    expect((await repo.watchConversation(chat.id).first)!.title, 'Kept');
  });

  test('replies in the language of the newest message', () async {
    final chat = await repo.createConversation(
      title: 'T',
      settings: const ConversationSettings(systemPrompt: 'Be kind.'),
    );
    String system() {
      final prompt = (engine.requests.last.prompt as RawPrompt).text;
      return prompt.substring(0, prompt.indexOf('<|eot_id|>'));
    }

    await send(chat, 'kemon acho?');
    expect(
      system(),
      endsWith('Be kind.\n\n${ReplyLanguage.bengali.instruction}'),
    );
    await send(chat, 'What is AI?');
    expect(system(), endsWith(ReplyLanguage.english.instruction));
    await send(chat, '2 + 2');
    expect(system(), endsWith(ReplyLanguage.english.instruction));
    await send(chat, 'তুমি কে?');
    expect(system(), endsWith(ReplyLanguage.bengali.instruction));
  });

  group('phone commands', () {
    late FakeDeviceActions actions;
    setUp(() {
      actions = FakeDeviceActions(
        apps: const [InstalledApp(label: 'YouTube', packageName: 'com.yt')],
      );
      responder = ChatResponder(
        engine: engine,
        models: library,
        repository: repo,
        threads: () => 3,
        actions: actions,
        clock: FixedClock(DateTime(2026, 10, 19, 21)),
      );
    });

    test('run without the model and are answered in their language', () async {
      final chat = await repo.createConversation(title: 'New chat');
      final events = await send(chat, 'সকাল ৭টায় অ্যালার্ম দাও');
      expect(events.single, isA<ReplyFinished>());
      expect(engine.loadRequests, isEmpty);
      expect(engine.requests, isEmpty);
      expect(actions.log, ['alarm 7:0']);
      final saved = await repo.messages(chat.id);
      expect(saved.map((m) => m.content), [
        'সকাল ৭টায় অ্যালার্ম দাও',
        'সকাল ৭:০০-এ অ্যালার্ম দেওয়া হয়েছে।',
      ]);
      expect(saved.last.role, MessageRole.assistant);
      expect(
        (await repo.watchConversation(chat.id).first)!.title,
        'সকাল ৭টায় অ্যালার্ম দাও',
      );

      await send(chat, 'open YouTube');
      expect(actions.log.last, 'open com.yt');
      expect((await repo.messages(chat.id)).last.content, 'Opening YouTube.');
    });

    test('an app that is not installed goes to the model', () async {
      final chat = await repo.createConversation(title: 'T');
      final events = await send(chat, 'open the door');
      expect(events.last, isA<ReplyFinished>());
      expect(engine.requests, hasLength(1));
      expect(actions.log, isEmpty);
    });

    test('platforms without actions send everything to the model', () async {
      responder = ChatResponder(
        engine: engine,
        models: library,
        repository: repo,
        threads: () => 3,
        actions: FakeDeviceActions(supported: false),
      );
      final chat = await repo.createConversation(title: 'T');
      await send(chat, 'torch on');
      expect(engine.requests, hasLength(1));
    });
  });

  test('waits for a reply a closed chat left running', () async {
    final chat = await repo.createConversation(title: 'T');
    await send(chat, 'First');
    engine.emitState(EngineState.generating); // still stopping
    final events = responder.send(conversation: chat, text: 'Second').toList();
    await pumpEventQueue();
    expect(engine.cancelled, isTrue, reason: 'the leftover reply is stopped');
    engine.emitState(EngineState.ready);
    expect((await events).last, isA<ReplyFinished>());
  });

  test('reports busy only when earlier work never stops', () async {
    responder = ChatResponder(
      engine: engine,
      models: library,
      repository: repo,
      threads: () => 3,
      busyWait: const Duration(milliseconds: 50),
    );
    final chat = await repo.createConversation(title: 'T');
    engine.emitState(EngineState.loading);
    final events = await send(chat, 'Hello');
    expect((events.last as ReplyFailed).failure, const EngineBusyFailure());
  });

  test('drops old history that does not fit and says so', () async {
    engine.tokenCounter = (text) => text.length; // 1 token per character
    final chat = await repo.createConversation(
      title: 'T',
      settings: const ConversationSettings(
        systemPrompt: '',
        contextLength: 1024,
        maxTokens: 128,
      ),
    );
    for (var i = 0; i < 6; i++) {
      await send(chat, 'question number $i ${'x' * 150}');
    }
    final started = (await send(chat, 'last')).whereType<ReplyStarted>().single;
    expect(started.droppedMessages, greaterThan(0));
    final reply = (await repo.messages(chat.id)).last;
    expect(reply.droppedMessages, started.droppedMessages);
    final prompt = (engine.requests.last.prompt as RawPrompt).text;
    expect(prompt, contains('last'));
    expect(prompt, isNot(contains('question number 0')));
  });

  test('uses the model family template and hides Qwen thinking', () async {
    library.set(LibraryState(installed: [installed('qwen-q4')]));
    final chat = await repo.createConversation(title: 'T');
    await send(chat, 'Hi');
    final prompt = (engine.requests.last.prompt as RawPrompt).text;
    expect(prompt, endsWith('<|im_start|>assistant\n<think>\n\n</think>\n\n'));
  });

  test('imported models use the template detected from the file', () async {
    library.set(
      LibraryState(
        installed: [
          InstalledModel(
            id: 'imported-x',
            displayName: 'x',
            fileName: 'imported-x.gguf',
            sizeBytes: 1,
            sha256: 'b' * 64,
            verification: ModelVerification.unverified,
            installedAt: DateTime.utc(2026),
          ),
        ],
      ),
    );
    final chat = await repo.createConversation(title: 'T');
    await send(chat, 'Hi');
    // The fake engine reports no embedded template: ChatML fallback.
    expect(
      (engine.requests.last.prompt as RawPrompt).text,
      contains('<|im_start|>user'),
    );
  });

  test('a stopped reply is kept as stopped', () async {
    engine = FakeInferenceEngine(
      tokens: List.filled(100, 'word '),
      tokenDelay: const Duration(milliseconds: 5),
    );
    responder = ChatResponder(
      engine: engine,
      models: library,
      repository: repo,
      threads: () => 2,
    );
    final chat = await repo.createConversation(title: 'T');
    final events = <ReplyEvent>[];
    await for (final event in responder.send(conversation: chat, text: 'Go')) {
      events.add(event);
      if (event is ReplyText && event.content.length > 20) {
        await responder.stop();
      }
    }
    final finished = events.last as ReplyFinished;
    expect(finished.message.status, MessageStatus.stopped);
    expect(finished.message.content, isNotEmpty);
    expect((await repo.messages(chat.id)).last.status, MessageStatus.stopped);
  });

  test('reports a missing model', () async {
    library.set(const LibraryState());
    final chat = await repo.createConversation(title: 'T');
    final events = await send(chat, 'Hi');
    expect(
      (events.single as ReplyFailed).failure,
      const NoModelLoadedFailure(),
    );
    expect((await repo.messages(chat.id)).single.role, MessageRole.user);
  });

  test('reports load and generation failures', () async {
    engine = FakeInferenceEngine(
      loadFailure: const ModelLoadFailure(
        ModelLoadFailureReason.insufficientMemory,
      ),
    );
    responder = ChatResponder(
      engine: engine,
      models: library,
      repository: repo,
      threads: () => 2,
    );
    final chat = await repo.createConversation(title: 'T');
    expect(
      ((await send(chat, 'Hi')).last as ReplyFailed).failure,
      isA<ModelLoadFailure>(),
    );

    engine = FakeInferenceEngine(
      generationFailure: const GenerationFailure('decode failed'),
    );
    responder = ChatResponder(
      engine: engine,
      models: library,
      repository: repo,
      threads: () => 2,
    );
    expect(
      ((await send(chat, 'Again')).last as ReplyFailed).failure,
      const GenerationFailure('decode failed'),
    );
    expect((await repo.messages(chat.id)).last.status, MessageStatus.failed);
  });

  test('picks the chosen model, falling back to the newest', () async {
    library.set(
      LibraryState(installed: [installed('newest'), installed('older')]),
    );
    final chat = await repo.createConversation(
      title: 'T',
      settings: const ConversationSettings(modelId: 'older'),
    );
    expect(responder.modelFor(chat)!.id, 'older');
    final gone = chat.copyWith(
      settings: const ConversationSettings(modelId: 'deleted'),
    );
    expect(responder.modelFor(gone)!.id, 'newest');
  });

  test('ignores empty messages', () async {
    final chat = await repo.createConversation(title: 'T');
    expect(await send(chat, '   '), isEmpty);
    expect(await repo.messages(chat.id), isEmpty);
  });

  group('runtime limits', () {
    ChatResponder limited(Set<RuntimeConcern> concerns) => ChatResponder(
      engine: engine,
      models: library,
      repository: repo,
      threads: () => 4,
      advice: () => RuntimeAdvice(concerns),
    );

    test('refuses to start when the phone is critically hot', () async {
      final chat = await repo.createConversation(title: 'T');
      final events = await limited({RuntimeConcern.overheated})
          .send(conversation: chat, text: 'Hi')
          .toList();
      expect(
        (events.single as ReplyFailed).failure,
        const RuntimeLimitFailure(RuntimeLimitReason.overheated),
      );
      expect(engine.loadRequests, isEmpty);
      // The question is kept so the user can ask again later.
      expect((await repo.messages(chat.id)).single.role, MessageRole.user);
    });

    test('refuses to start when the battery is nearly empty', () async {
      final chat = await repo.createConversation(title: 'T');
      final events = await limited({RuntimeConcern.criticalBattery})
          .send(conversation: chat, text: 'Hi')
          .toList();
      expect(
        (events.single as ReplyFailed).failure,
        const RuntimeLimitFailure(RuntimeLimitReason.batteryCritical),
      );
    });

    test('uses half the threads when warm, all of them otherwise', () async {
      final chat = await repo.createConversation(title: 'T');
      await limited({RuntimeConcern.warm})
          .send(conversation: chat, text: 'Hi')
          .toList();
      // The fake model was loaded with 4 threads.
      expect(engine.requests.last.threads, 2);

      await limited(const {}).send(conversation: chat, text: 'Again').toList();
      expect(engine.requests.last.threads, isNull);
    });
  });

  test(
    'reloads once when the model is freed before the reply starts',
    () async {
      engine.unloadAfterNextLoad = true;
      final chat = await repo.createConversation(title: 'T');
      final events = await send(chat, 'Hi');
      expect(events.last, isA<ReplyFinished>());
      expect((events.last as ReplyFinished).message.content, 'Hello there!');
      expect(engine.loadRequests, hasLength(2));
      final saved = await repo.messages(chat.id);
      expect(saved.map((m) => m.role), [
        MessageRole.user,
        MessageRole.assistant,
      ]);
    },
  );
}
