import 'package:emberwit/core/utils/clock.dart';
import 'package:emberwit/features/chat/data/chat_database.dart';
import 'package:emberwit/features/chat/data/chat_repository_impl.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/chat_db.dart';

void main() {
  late ChatDatabase db;
  late FixedClock clock;
  late ChatRepositoryImpl repo;

  setUp(() {
    db = memoryChatDatabase();
    clock = FixedClock(DateTime.utc(2026, 9, 24, 8));
    repo = ChatRepositoryImpl(db, clock: clock);
  });
  tearDown(() => db.close());

  ChatMessage message(
    String conversationId,
    String content, {
    MessageRole role = MessageRole.user,
    String id = '',
  }) => ChatMessage(
    id: id.isEmpty ? '$conversationId-$content' : id,
    conversationId: conversationId,
    role: role,
    content: content,
    createdAt: clock.now(),
  );

  test('creates conversations with settings', () async {
    const settings = ConversationSettings(
      modelId: 'qwen3-0.6b-q4_k_m',
      temperature: 0.2,
      contextLength: 4096,
    );
    final created = await repo.createConversation(
      title: 'New chat',
      settings: settings,
    );
    final stored = await repo.watchConversation(created.id).first;
    expect(stored!.title, 'New chat');
    expect(stored.settings, settings);
    expect(stored.pinned, isFalse);
  });

  test('lists pinned first, then most recently updated', () async {
    final a = await repo.createConversation(title: 'A');
    clock.advance(const Duration(minutes: 1));
    final b = await repo.createConversation(title: 'B');
    clock.advance(const Duration(minutes: 1));
    final c = await repo.createConversation(title: 'C');
    await repo.setPinned(a.id, pinned: true);
    clock.advance(const Duration(minutes: 1));
    await repo.saveMessage(message(b.id, 'hi'));

    final list = await repo.watchConversations().first;
    expect(list.map((x) => x.title), ['A', 'B', 'C']);
    expect(list[1].preview, 'hi');
    expect(c.id, isNotEmpty);
  });

  test('search matches titles and message text, safely', () async {
    final trip = await repo.createConversation(title: 'Trip to Sylhet');
    final other = await repo.createConversation(title: 'Other');
    await repo.saveMessage(message(other.id, 'বন্যার সময় কী করব?'));
    await repo.createConversation(title: '100% sure_thing');

    Future<List<String>> search(String q) async =>
        (await repo.watchConversations(query: q).first)
            .map((c) => c.title)
            .toList();

    expect(await search('sylhet'), ['Trip to Sylhet']);
    expect(await search('বন্যা'), ['Other']);
    expect(await search('%'), ['100% sure_thing'], reason: 'LIKE is escaped');
    expect(await search('_'), ['100% sure_thing']);
    expect(await search('nothing'), isEmpty);
    expect(await search('  '), hasLength(3));
    expect(trip.id, isNotEmpty);
  });

  test('stores messages in order with stats; upserts by id', () async {
    final chat = await repo.createConversation(title: 'T');
    await repo.saveMessage(message(chat.id, 'q'));
    clock.advance(const Duration(seconds: 1));
    final reply = ChatMessage(
      id: 'r1',
      conversationId: chat.id,
      role: MessageRole.assistant,
      content: '',
      createdAt: clock.now(),
      status: MessageStatus.streaming,
      modelId: 'm',
      droppedMessages: 2,
    );
    await repo.saveMessage(reply);
    await repo.saveMessage(
      reply.copyWith(
        content: '<think>x</think>Answer',
        status: MessageStatus.complete,
        stats: const MessageStats(
          promptTokens: 10,
          generatedTokens: 5,
          timeToFirstTokenMs: 300,
          tokensPerSecond: 12.5,
        ),
      ),
    );
    final messages = await repo.messages(chat.id);
    expect(messages.map((m) => m.role), [
      MessageRole.user,
      MessageRole.assistant,
    ]);
    final saved = messages.last;
    expect(saved.status, MessageStatus.complete);
    expect(saved.stats!.totalTokens, 15);
    expect(saved.droppedMessages, 2);
    expect(saved.modelId, 'm');
    final conversation = await repo.watchConversation(chat.id).first;
    expect(conversation!.preview, 'Answer', reason: 'thinking stripped');
  });

  test('renames, updates settings and deletes', () async {
    final chat = await repo.createConversation(title: 'Old');
    await repo.rename(chat.id, '  New  ');
    await repo.updateSettings(
      chat.id,
      const ConversationSettings(maxTokens: 1024),
    );
    await repo.saveMessage(message(chat.id, 'x'));
    var stored = await repo.watchConversation(chat.id).first;
    expect(stored!.title, 'New');
    expect(stored.settings.maxTokens, 1024);

    await repo.deleteMessage('${chat.id}-x');
    expect(await repo.messages(chat.id), isEmpty);

    await repo.deleteConversation(chat.id);
    stored = await repo.watchConversation(chat.id).first;
    expect(stored, isNull);
  });

  test('deleteAll removes everything', () async {
    final a = await repo.createConversation(title: 'A');
    await repo.saveMessage(message(a.id, 'x'));
    await repo.createConversation(title: 'B');
    await repo.deleteAll();
    expect(await repo.watchConversations().first, isEmpty);
    expect(await repo.messages(a.id), isEmpty);
  });

  test('long previews are shortened', () async {
    final chat = await repo.createConversation(title: 'T');
    await repo.saveMessage(message(chat.id, 'x' * 500));
    final stored = await repo.watchConversation(chat.id).first;
    expect(stored!.preview.length, ChatRepositoryImpl.previewLength);
  });
}
