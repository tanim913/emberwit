import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_models.freezed.dart';

/// Default instructions for new conversations. English, because small models
/// follow English instructions most reliably; the model is told to answer in
/// the user's language, so Bengali questions get Bengali answers.
const String defaultSystemPrompt =
    'You are Emberwit, a helpful assistant running entirely offline on the '
    "user's phone. Answer clearly and concisely. Always reply in the "
    'language the user writes in (for example Bengali or English).';

/// Settings that shape one conversation.
@freezed
abstract class ConversationSettings with _$ConversationSettings {
  /// Creates settings with defaults suited to phones.
  const factory({
    /// Installed model id, or `null` to pick one when sending.
    String? modelId,

    /// Instructions given to the model before the conversation.
    @Default(defaultSystemPrompt) String systemPrompt,

    /// Sampling temperature, 0 to 2.
    @Default(0.7) double temperature,

    /// Nucleus sampling, 0.05 to 1.
    @Default(0.95) double topP,

    /// Context window in tokens.
    @Default(2048) int contextLength,

    /// Maximum reply length in tokens.
    @Default(512) int maxTokens,
  }) = _ConversationSettings;
}

/// A conversation.
@freezed
abstract class Conversation with _$Conversation {
  /// Creates a conversation.
  const factory({
    required String id,

    /// Title shown in the list.
    required String title,

    required DateTime createdAt,

    /// Time of the last message or change.
    required DateTime updatedAt,

    /// Pinned conversations are listed first.
    @Default(false) bool pinned,

    @Default(ConversationSettings()) ConversationSettings settings,

    /// Start of the last message, for the list.
    @Default('') String preview,
  }) = _Conversation;
}

/// Who wrote a message.
enum MessageRole {
  /// The person.
  user,

  /// The model.
  assistant,
}

/// Lifecycle of a message.
enum MessageStatus {
  /// Finished.
  complete,

  /// Being generated.
  streaming,

  /// Stopped by the user; content is partial.
  stopped,

  /// Generation failed.
  failed,
}

/// Measurements of one reply.
@freezed
abstract class MessageStats with _$MessageStats {
  /// Creates stats.
  const factory({
    required int promptTokens,
    required int generatedTokens,
    required int timeToFirstTokenMs,
    required double tokensPerSecond,
  }) = _MessageStats;

  const new _();

  /// Tokens in the context after this reply.
  int get totalTokens => promptTokens + generatedTokens;
}

/// One message.
@freezed
abstract class ChatMessage with _$ChatMessage {
  /// Creates a message.
  const factory({
    required String id,
    required String conversationId,
    required MessageRole role,
    required String content,
    required DateTime createdAt,
    @Default(MessageStatus.complete) MessageStatus status,

    /// Model that wrote an assistant message.
    String? modelId,

    /// Reply measurements.
    MessageStats? stats,

    /// Older messages left out of the model's context for this reply.
    @Default(0) int droppedMessages,
  }) = _ChatMessage;
}
