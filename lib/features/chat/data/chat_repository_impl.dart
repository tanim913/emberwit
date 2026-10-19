import 'package:drift/drift.dart';
import 'package:emberwit/core/utils/clock.dart';
import 'package:emberwit/features/chat/data/chat_database.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:emberwit/features/chat/domain/chat_repository.dart';
import 'package:emberwit/features/chat/domain/chat_template.dart';
import 'package:uuid/uuid.dart';

/// [ChatRepository] on the encrypted drift database.
final class ChatRepositoryImpl implements ChatRepository {
  /// Creates the repository.
  new(this._db, {this._clock = const SystemClock(), this._uuid = const Uuid()});

  final ChatDatabase _db;
  final Clock _clock;
  final Uuid _uuid;

  /// Characters of the last message kept as the list preview.
  static const int previewLength = 120;

  @override
  Stream<List<Conversation>> watchConversations({String query = ''}) {
    final select = _db.select(_db.conversations);
    final text = query.trim();
    if (text.isNotEmpty) {
      final pattern = '%${_escapeLike(text)}%';
      select.where(
        (c) =>
            c.title.like(pattern, escapeChar: r'\') |
            existsQuery(
              _db.select(_db.messages)..where(
                (m) =>
                    m.conversationId.equalsExp(c.id) &
                    m.content.like(pattern, escapeChar: r'\'),
              ),
            ),
      );
    }
    select.orderBy([
      (c) => OrderingTerm.desc(c.pinned),
      (c) => OrderingTerm.desc(c.updatedAt),
    ]);
    return select.watch().map((rows) => rows.map(_toConversation).toList());
  }

  @override
  Stream<Conversation?> watchConversation(String id) =>
      (_db.select(_db.conversations)..where((c) => c.id.equals(id)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : _toConversation(row));

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) =>
      _messagesQuery(conversationId)
          .watch()
          .map((rows) => rows.map(_toMessage).toList());

  @override
  Future<List<ChatMessage>> messages(String conversationId) async =>
      (await _messagesQuery(conversationId).get()).map(_toMessage).toList();

  SimpleSelectStatement<$MessagesTable, MessageRow> _messagesQuery(
    String conversationId,
  ) => _db.select(_db.messages)
    ..where((m) => m.conversationId.equals(conversationId))
    ..orderBy([
      (m) => OrderingTerm.asc(m.createdAt),
      (m) => OrderingTerm.asc(m.rowId),
    ]);

  @override
  Future<Conversation> createConversation({
    required String title,
    ConversationSettings settings = const ConversationSettings(),
  }) async {
    final now = _clock.now();
    final conversation = Conversation(
      id: _uuid.v4(),
      title: title,
      createdAt: now,
      updatedAt: now,
      settings: settings,
    );
    await _db
        .into(_db.conversations)
        .insert(
          ConversationsCompanion.insert(
            id: conversation.id,
            title: title,
            createdAt: now,
            updatedAt: now,
            modelId: Value(settings.modelId),
            systemPrompt: settings.systemPrompt,
            temperature: settings.temperature,
            topP: settings.topP,
            contextLength: settings.contextLength,
            maxTokens: settings.maxTokens,
          ),
        );
    return conversation;
  }

  @override
  Future<void> rename(String id, String title) =>
      _update(id, ConversationsCompanion(title: Value(title.trim())));

  @override
  Future<void> setPinned(String id, {required bool pinned}) =>
      _update(id, ConversationsCompanion(pinned: Value(pinned)));

  @override
  Future<void> updateSettings(String id, ConversationSettings settings) =>
      _update(
        id,
        ConversationsCompanion(
          modelId: Value(settings.modelId),
          systemPrompt: Value(settings.systemPrompt),
          temperature: Value(settings.temperature),
          topP: Value(settings.topP),
          contextLength: Value(settings.contextLength),
          maxTokens: Value(settings.maxTokens),
        ),
      );

  Future<void> _update(String id, ConversationsCompanion changes) =>
      (_db.update(
        _db.conversations,
      )..where((c) => c.id.equals(id))).write(changes);

  @override
  Future<void> deleteConversation(String id) =>
      (_db.delete(_db.conversations)..where((c) => c.id.equals(id))).go();

  @override
  Future<void> deleteAll() => _db.transaction(() async {
    await _db.delete(_db.messages).go();
    await _db.delete(_db.conversations).go();
  });

  @override
  Future<void> saveMessage(ChatMessage message) => _db.transaction(() async {
    final stats = message.stats;
    await _db
        .into(_db.messages)
        .insertOnConflictUpdate(
          MessagesCompanion.insert(
            id: message.id,
            conversationId: message.conversationId,
            role: message.role.name,
            content: message.content,
            status: message.status.name,
            createdAt: message.createdAt,
            modelId: Value(message.modelId),
            promptTokens: Value(stats?.promptTokens),
            generatedTokens: Value(stats?.generatedTokens),
            timeToFirstTokenMs: Value(stats?.timeToFirstTokenMs),
            tokensPerSecond: Value(stats?.tokensPerSecond),
            droppedMessages: Value(message.droppedMessages),
          ),
        );
    final preview = stripThinking(message.content).trim();
    await _update(
      message.conversationId,
      ConversationsCompanion(
        updatedAt: Value(_clock.now()),
        preview: Value(
          preview.length > previewLength
              ? preview.substring(0, previewLength)
              : preview,
        ),
      ),
    );
  });

  @override
  Future<void> deleteMessage(String id) =>
      (_db.delete(_db.messages)..where((m) => m.id.equals(id))).go();

  @override
  Future<List<Conversation>> allConversations() => watchConversations().first;

  @override
  Future<int> conversationCount() async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM conversations',
          readsFrom: {_db.conversations},
        )
        .getSingle();
    return row.read<int>('n');
  }

  @override
  Future<bool> restoreConversation(
    Conversation conversation,
    List<ChatMessage> messages,
  ) => _db.transaction(() async {
    final existing = await (_db.select(
      _db.conversations,
    )..where((c) => c.id.equals(conversation.id))).getSingleOrNull();
    if (existing != null) return false;
    final settings = conversation.settings;
    await _db
        .into(_db.conversations)
        .insert(
          ConversationsCompanion.insert(
            id: conversation.id,
            title: conversation.title,
            pinned: Value(conversation.pinned),
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            preview: Value(conversation.preview),
            modelId: Value(settings.modelId),
            systemPrompt: settings.systemPrompt,
            temperature: settings.temperature,
            topP: settings.topP,
            contextLength: settings.contextLength,
            maxTokens: settings.maxTokens,
          ),
        );
    await _db.batch((batch) {
      batch.insertAll(_db.messages, [
        for (final m in messages)
          MessagesCompanion.insert(
            id: m.id,
            conversationId: conversation.id,
            role: m.role.name,
            content: m.content,
            status: m.status.name,
            createdAt: m.createdAt,
            modelId: Value(m.modelId),
            promptTokens: Value(m.stats?.promptTokens),
            generatedTokens: Value(m.stats?.generatedTokens),
            timeToFirstTokenMs: Value(m.stats?.timeToFirstTokenMs),
            tokensPerSecond: Value(m.stats?.tokensPerSecond),
            droppedMessages: Value(m.droppedMessages),
          ),
      ], mode: InsertMode.insertOrIgnore);
    });
    return true;
  });

  static String _escapeLike(String text) => text
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  static Conversation _toConversation(ConversationRow row) => Conversation(
    id: row.id,
    title: row.title,
    pinned: row.pinned,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    preview: row.preview,
    settings: ConversationSettings(
      modelId: row.modelId,
      systemPrompt: row.systemPrompt,
      temperature: row.temperature,
      topP: row.topP,
      contextLength: row.contextLength,
      maxTokens: row.maxTokens,
    ),
  );

  static ChatMessage _toMessage(MessageRow row) => ChatMessage(
    id: row.id,
    conversationId: row.conversationId,
    role: MessageRole.values.byName(row.role),
    content: row.content,
    createdAt: row.createdAt,
    status: MessageStatus.values.byName(row.status),
    modelId: row.modelId,
    droppedMessages: row.droppedMessages,
    stats: row.generatedTokens == null
        ? null
        : MessageStats(
            promptTokens: row.promptTokens ?? 0,
            generatedTokens: row.generatedTokens!,
            timeToFirstTokenMs: row.timeToFirstTokenMs ?? 0,
            tokensPerSecond: row.tokensPerSecond ?? 0,
          ),
  );
}
