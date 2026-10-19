@Tags(['golden'])
library;

import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:emberwit/features/chat/presentation/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_harness.dart';

const Map<String, ({String question, String answer})> _answers = {
  'en': (
    question: 'What should I pack for a flood?',
    answer:
        'Pack these first:\n\n'
        '1. **Drinking water** for three days\n'
        '2. A torch and spare batteries\n'
        '3. Copies of IDs in a waterproof bag\n\n'
        'Save the emergency numbers:\n\n'
        '```text\nNational emergency: 999\n```',
  ),
  'bn': (
    question: 'বন্যার জন্য কী গুছিয়ে রাখব?',
    answer:
        'প্রথমে এগুলো গুছিয়ে রাখুন:\n\n'
        '1. তিন দিনের **খাবার পানি**\n'
        '2. টর্চ ও বাড়তি ব্যাটারি\n'
        '3. পরিচয়পত্রের কপি, জলরোধী ব্যাগে\n\n'
        'জরুরি নম্বর সংরক্ষণ করুন:\n\n'
        '```text\nজাতীয় জরুরি সেবা: ৯৯৯\n```',
  ),
};

void main() {
  for (final locale in const [Locale('en'), Locale('bn')]) {
    for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('chat ${locale.languageCode} ${mode.name}', (tester) async {
        final h = ChatHarness();
        final text = _answers[locale.languageCode]!;
        late Conversation chat;
        await tester.runAsync(() async {
          chat = await h.repository.createConversation(title: text.question);
          await h.repository.saveMessage(
            ChatMessage(
              id: 'q',
              conversationId: chat.id,
              role: MessageRole.user,
              content: text.question,
              createdAt: DateTime.utc(2026, 9, 24, 12),
            ),
          );
          await h.repository.saveMessage(
            ChatMessage(
              id: 'a',
              conversationId: chat.id,
              role: MessageRole.assistant,
              content: text.answer,
              createdAt: DateTime.utc(2026, 9, 24, 12, 1),
              modelId: 'qwen3-q4',
              stats: const MessageStats(
                promptTokens: 96,
                generatedTokens: 71,
                timeToFirstTokenMs: 480,
                tokensPerSecond: 14.2,
              ),
            ),
          );
        });
        await h.pump(
          tester,
          ChatPage(conversationId: chat.id),
          locale: locale,
          themeMode: mode,
        );
        await expectLater(
          find.byType(ChatPage),
          matchesGoldenFile(
            '../../../goldens/goldens/'
            'chat_${locale.languageCode}_${mode.name}.png',
          ),
        );
        await h.dispose(tester);
      });
    }
  }
}
