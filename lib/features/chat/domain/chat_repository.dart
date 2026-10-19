import 'package:emberwit/features/chat/domain/chat_models.dart';

/// Stores conversations and messages. All data stays on the device, in the
/// encrypted database.
abstract interface class ChatRepository {
  /// Conversations, pinned first, then most recent. When [query] is not
  /// empty, only conversations whose title or messages contain it.
  Stream<List<Conversation>> watchConversations({String query = ''});

  /// One conversation, `null` once deleted.
  Stream<Conversation?> watchConversation(String id);

  /// Messages of a conversation, oldest first.
  Stream<List<ChatMessage>> watchMessages(String conversationId);

  /// Messages of a conversation, oldest first.
  Future<List<ChatMessage>> messages(String conversationId);

  /// Creates a conversation.
  Future<Conversation> createConversation({
    required String title,
    ConversationSettings settings = const ConversationSettings(),
  });

  /// Renames a conversation.
  Future<void> rename(String id, String title);

  /// Pins or unpins a conversation.
  Future<void> setPinned(String id, {required bool pinned});

  /// Replaces a conversation's settings.
  Future<void> updateSettings(String id, ConversationSettings settings);

  /// Deletes a conversation and its messages.
  Future<void> deleteConversation(String id);

  /// Deletes every conversation.
  Future<void> deleteAll();

  /// Inserts or replaces a message and touches its conversation.
  Future<void> saveMessage(ChatMessage message);

  /// Deletes one message.
  Future<void> deleteMessage(String id);

  /// Every conversation, pinned first, then most recent.
  Future<List<Conversation>> allConversations();

  /// Number of conversations.
  Future<int> conversationCount();

  /// Stores [conversation] and its [messages] exactly as given (ids, times,
  /// settings), for restoring an export. Returns `false` and changes nothing
  /// when a conversation with the same id already exists.
  Future<bool> restoreConversation(
    Conversation conversation,
    List<ChatMessage> messages,
  );
}
