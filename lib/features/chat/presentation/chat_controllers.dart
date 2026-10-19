import 'dart:async';

import 'package:emberwit/core/device/device_profile.dart';
import 'package:emberwit/core/device/device_profile_repository.dart';
import 'package:emberwit/core/device/device_tier_classifier.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/preferences/general_preferences.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/features/chat/data/chat_providers.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:emberwit/features/chat/domain/chat_responder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_controllers.freezed.dart';
part 'chat_controllers.g.dart';

/// Conversations matching [query], pinned first, newest first.
@riverpod
Stream<List<Conversation>> conversations(Ref ref, String query) =>
    ref.watch(chatRepositoryProvider).watchConversations(query: query);

/// Installed models, kept up to date.
@riverpod
Stream<List<InstalledModel>> installedModels(Ref ref) async* {
  final library = ref.watch(modelLibraryProvider);
  await library.initialize();
  yield library.state.installed;
  yield* library.changes.map((s) => s.installed);
}

/// Settings for a new conversation: the default model when it is still
/// installed, else the newest installed model, and the device tier's context
/// length capped by the model's recommendation.
ConversationSettings newConversationSettings({
  required List<InstalledModel> installed,
  DeviceProfile? profile,
  String? defaultModelId,
}) {
  InstalledModel? model;
  for (final m in installed) {
    if (m.id == defaultModelId) model = m;
  }
  model ??= installed.isEmpty ? null : installed.first;
  final tierContext = profile == null
      ? 2048
      : defaultContextLength(const DeviceTierClassifier().classify(profile));
  final modelContext = model?.catalogEntry?.recommendedContextLength ?? 4096;
  return ConversationSettings(
    modelId: model?.id,
    contextLength: tierContext < modelContext ? tierContext : modelContext,
  );
}

/// Creates an empty conversation titled [title] with the settings of
/// [newConversationSettings], and returns its id.
Future<String> createConversation(
  WidgetRef ref, {
  required String title,
}) async {
  // Read the library directly: an auto-disposing provider's future would
  // never complete without a listener.
  final library = ref.read(modelLibraryProvider);
  await library.initialize();
  final installed = library.state.installed;
  final profile = await ref
      .read(deviceProfileRepositoryProvider)
      .cachedProfile();
  final conversation = await ref
      .read(chatRepositoryProvider)
      .createConversation(
        title: title,
        settings: newConversationSettings(
          installed: installed,
          profile: profile,
          defaultModelId: ref.read(defaultModelIdProvider),
        ),
      );
  return conversation.id;
}

/// Id of an untouched conversation titled [title] among the most recent
/// ones, else of a new one. Repeated taps on the voice widget then do not
/// leave a trail of empty chats.
Future<String> reuseEmptyConversation(
  WidgetRef ref, {
  required String title,
}) async {
  final repository = ref.read(chatRepositoryProvider);
  final recent = await repository.watchConversations().first;
  for (final conversation in recent.take(5)) {
    if (conversation.title == title &&
        (await repository.messages(conversation.id)).isEmpty) {
      return conversation.id;
    }
  }
  return await createConversation(ref, title: title);
}

/// What the chat screen shows.
@freezed
abstract class ChatViewState with _$ChatViewState {
  /// Creates the state.
  const factory({
    /// The conversation; `null` until loaded or after deletion.
    Conversation? conversation,

    /// Saved messages, oldest first.
    @Default(<ChatMessage>[]) List<ChatMessage> messages,

    /// A reply is being produced.
    @Default(false) bool generating,

    /// Model load progress while the model loads.
    double? loadProgress,

    /// Id of the assistant message being streamed.
    String? liveMessageId,

    /// Text of the streamed reply so far.
    @Default('') String liveContent,

    /// Why the last reply failed.
    AppFailure? failure,
  }) = _ChatViewState;

  const new _();

  /// Messages with the live reply merged in. A message left "streaming" by
  /// an interrupted session is shown as stopped.
  List<ChatMessage> get visibleMessages => [
    for (final m in messages)
      if (m.id == liveMessageId)
        m.copyWith(content: liveContent)
      else if (m.status == MessageStatus.streaming)
        m.copyWith(status: MessageStatus.stopped)
      else
        m,
  ];
}

/// Drives one conversation: loads messages, sends, streams, stops.
@riverpod
class ChatController extends _$ChatController {
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _flush;
  String _pending = '';
  bool _generating = false;

  /// How often streamed text is pushed to the UI. Coalescing tokens keeps
  /// markdown re-rendering well inside the frame budget.
  static const Duration flushInterval = Duration(milliseconds: 50);

  @override
  ChatViewState build(String conversationId) {
    final repository = ref.watch(chatRepositoryProvider);
    final responder = ref.watch(chatResponderProvider);
    _subscriptions.addAll([
      repository
          .watchConversation(conversationId)
          .listen((c) => state = state.copyWith(conversation: c)),
      repository
          .watchMessages(conversationId)
          .listen((m) => state = state.copyWith(messages: m)),
    ]);
    ref.onDispose(() {
      for (final s in _subscriptions) {
        unawaited(s.cancel());
      }
      _flush?.cancel();
      // Leaving the chat stops the reply; the partial text is kept.
      if (_generating) unawaited(responder.stop());
    });
    return const ChatViewState();
  }

  /// Sends [text]. [untitled] is the placeholder title to replace.
  Future<void> send(String text, {required String untitled}) async {
    final conversation = state.conversation;
    if (conversation == null || state.generating || text.trim().isEmpty) {
      return;
    }
    _generating = true;
    state = state.copyWith(
      generating: true,
      failure: null,
      loadProgress: null,
      liveMessageId: null,
      liveContent: '',
    );
    final replies = ref
        .read(chatResponderProvider)
        .send(conversation: conversation, text: text, untitled: untitled);
    try {
      await _follow(replies);
    } on Object catch (error, stackTrace) {
      // Never leave the chat stuck "replying" with nothing on screen: any
      // unexpected error ends the reply with a visible failure.
      ref
          .read(appLoggerProvider)
          .error('Reply failed: ${error.runtimeType}', null, stackTrace);
      _flush?.cancel();
      _flush = null;
      if (ref.mounted) {
        state = state.copyWith(
          failure: const UnexpectedFailure(),
          loadProgress: null,
          liveMessageId: null,
          liveContent: '',
        );
      }
    } finally {
      _generating = false;
      if (ref.mounted) state = state.copyWith(generating: false);
    }
  }

  Future<void> _follow(Stream<ReplyEvent> replies) async {
    await for (final event in replies) {
      if (!ref.mounted) return;
      switch (event) {
        case ReplyLoadingModel(:final fraction):
          state = state.copyWith(loadProgress: fraction);
        case ReplyStarted(:final message):
          state = state.copyWith(loadProgress: null, liveMessageId: message.id);
        case ReplyText(:final content):
          _pending = content;
          _flush ??= Timer(flushInterval, _pushPending);
        case ReplyFinished():
          _flush?.cancel();
          _flush = null;
          state = state.copyWith(liveMessageId: null, liveContent: '');
        case ReplyFailed(:final failure):
          _flush?.cancel();
          _flush = null;
          state = state.copyWith(
            failure: failure,
            loadProgress: null,
            liveMessageId: null,
            liveContent: '',
          );
      }
    }
  }

  void _pushPending() {
    _flush = null;
    if (ref.mounted) state = state.copyWith(liveContent: _pending);
  }

  /// Stops the reply.
  Future<void> stop() => ref.read(chatResponderProvider).stop();

  /// Saves new settings for this conversation.
  Future<void> updateSettings(ConversationSettings settings) =>
      ref.read(chatRepositoryProvider).updateSettings(conversationId, settings);

  /// Hides the last error.
  void dismissFailure() => state = state.copyWith(failure: null);
}
