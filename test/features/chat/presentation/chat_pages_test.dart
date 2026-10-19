import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/widgets/error_banner.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:emberwit/features/chat/presentation/chat_page.dart';
import 'package:emberwit/features/chat/presentation/conversations_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_inference_engine.dart';
import 'chat_harness.dart';

void main() {
  group('ConversationsPage', () {
    testWidgets('shows the empty state', (tester) async {
      final h = ChatHarness();
      await h.pump(tester, const ConversationsPage());
      expect(find.textContaining('No chats yet'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('new chat creates a conversation with the newest model', (
      tester,
    ) async {
      final h = ChatHarness();
      await h.pump(tester, const ConversationsPage());
      await tester.tap(find.byKey(const Key('new-chat')));
      await h.settle(tester);
      late List<Conversation> all;
      await tester.runAsync(() async {
        all = await h.repository.watchConversations().first;
      });
      expect(all.single.title, 'New chat');
      expect(all.single.settings.modelId, 'qwen3-q4');
      expect(find.byType(ChatPage), findsOneWidget, reason: 'opened');
      await h.dispose(tester);
    });

    testWidgets('lists, searches, pins, renames and deletes', (tester) async {
      final h = ChatHarness();
      late Conversation flood;
      await tester.runAsync(() async {
        flood = await h.repository.createConversation(title: 'Flood safety');
        await h.repository.createConversation(title: 'Recipes');
      });
      await h.pump(tester, const ConversationsPage());
      expect(find.text('Flood safety'), findsOneWidget);
      expect(find.text('Recipes'), findsOneWidget);

      await tester.enterText(find.byType(SearchBar), 'flood');
      await h.settle(tester);
      expect(find.text('Recipes'), findsNothing);
      await tester.enterText(find.byType(SearchBar), 'zzz');
      await h.settle(tester);
      expect(find.textContaining('No chats match'), findsOneWidget);
      await tester.enterText(find.byType(SearchBar), '');
      await h.settle(tester);

      Future<void> menu(String item) async {
        await tester.tap(find.byKey(Key('conversation-menu-${flood.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(item).last);
        await tester.pumpAndSettle();
      }

      await menu('Pin');
      await h.settle(tester);
      expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);

      await menu('Rename');
      await tester.enterText(find.byKey(const Key('rename-field')), 'Floods');
      await tester.tap(find.byKey(const Key('rename-save')));
      await h.settle(tester);
      expect(find.text('Floods'), findsOneWidget);

      await menu('Delete');
      await tester.tap(find.byKey(const Key('confirm-delete-chat')));
      await h.settle(tester);
      expect(find.text('Floods'), findsNothing);
      await h.dispose(tester);
    });
  });

  group('ChatPage', () {
    testWidgets('sends a message and shows the streamed reply with stats', (
      tester,
    ) async {
      final h = ChatHarness();
      late Conversation chat;
      await tester.runAsync(() async {
        chat = await h.repository.createConversation(title: 'New chat');
      });
      await h.pump(tester, ChatPage(conversationId: chat.id));
      await tester.enterText(find.byKey(const Key('chat-input')), 'Hello?');
      await tester.tap(find.byKey(const Key('chat-send')));
      await h.settle(tester);
      expect(find.text('Hello?'), findsWidgets);
      expect(find.text('Hi there'), findsOneWidget);
      expect(find.textContaining('tokens/s'), findsOneWidget);
      expect(find.byKey(const Key('chat-send')), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('an unexpected error is shown and frees the chat', (
      tester,
    ) async {
      final h = ChatHarness();
      h.engine.throwOnGenerate = true;
      late Conversation chat;
      await tester.runAsync(() async {
        chat = await h.repository.createConversation(title: 'New chat');
      });
      await h.pump(tester, ChatPage(conversationId: chat.id));
      await tester.enterText(find.byKey(const Key('chat-input')), 'Hello?');
      await tester.tap(find.byKey(const Key('chat-send')));
      await h.settle(tester);
      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.byKey(const Key('chat-stop')), findsNothing);
      expect(find.byKey(const Key('chat-send')), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('stop ends a long reply and marks it stopped', (tester) async {
      final h = ChatHarness(
        engine: FakeInferenceEngine(
          tokens: List.filled(200, 'word '),
          tokenDelay: const Duration(milliseconds: 5),
        ),
      );
      late Conversation chat;
      await tester.runAsync(() async {
        chat = await h.repository.createConversation(title: 'T');
      });
      await h.pump(tester, ChatPage(conversationId: chat.id));
      await tester.enterText(find.byKey(const Key('chat-input')), 'Go on');
      await tester.tap(find.byKey(const Key('chat-send')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
      expect(find.byKey(const Key('chat-stop')), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat-stop')));
      await h.settle(tester);
      expect(find.text('Stopped'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('explains when no model is installed', (tester) async {
      final h = ChatHarness()..library.set(const LibraryState());
      late Conversation chat;
      await tester.runAsync(() async {
        chat = await h.repository.createConversation(title: 'T');
      });
      await h.pump(tester, ChatPage(conversationId: chat.id));
      expect(find.text('No model yet'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('shows the context trimmed notice and failures', (
      tester,
    ) async {
      final h = ChatHarness();
      late Conversation chat;
      await tester.runAsync(() async {
        chat = await h.repository.createConversation(title: 'T');
        await h.repository.saveMessage(
          ChatMessage(
            id: 'a',
            conversationId: chat.id,
            role: MessageRole.assistant,
            content: 'Short answer',
            createdAt: DateTime.utc(2026),
            droppedMessages: 3,
          ),
        );
        await h.repository.saveMessage(
          ChatMessage(
            id: 'b',
            conversationId: chat.id,
            role: MessageRole.assistant,
            content: 'Half',
            createdAt: DateTime.utc(2026, 1, 2),
            status: MessageStatus.failed,
          ),
        );
      });
      await h.pump(tester, ChatPage(conversationId: chat.id));
      expect(
        find.textContaining('3 earlier messages were left out'),
        findsOneWidget,
      );
      expect(find.text('This reply could not be finished.'), findsOneWidget);
      await h.dispose(tester);
    });

    testWidgets('settings are edited and saved', (tester) async {
      final h = ChatHarness();
      late Conversation chat;
      await tester.runAsync(() async {
        chat = await h.repository.createConversation(title: 'T');
      });
      await h.pump(tester, ChatPage(conversationId: chat.id));
      await tester.tap(find.byKey(const Key('chat-settings')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('settings-system-prompt')),
        'Answer like a pirate.',
      );
      await tester.tap(find.text('4K'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settings-save')));
      await tester.tap(find.byKey(const Key('settings-save')));
      await h.settle(tester);
      late Conversation stored;
      await tester.runAsync(() async {
        stored = (await h.repository.watchConversation(chat.id).first)!;
      });
      expect(stored.settings.systemPrompt, 'Answer like a pirate.');
      expect(stored.settings.contextLength, 4096);
      await h.dispose(tester);
    });
  });
}
