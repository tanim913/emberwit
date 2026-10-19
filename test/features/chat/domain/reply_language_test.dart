import 'package:emberwit/features/chat/domain/reply_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detect', () {
    for (final (text, expected) in [
      ('How are you?', ReplyLanguage.english),
      ('Explain photosynthesis', ReplyLanguage.english),
      ('hi', ReplyLanguage.english),
      ('I want chai', ReplyLanguage.english),
      ("Translate 'আমি ভাত খাই' into English", ReplyLanguage.english),
      ('তুমি কেমন আছো?', ReplyLanguage.bengali),
      ('আমাকে AI নিয়ে বলো', ReplyLanguage.bengali),
      ('kemon acho?', ReplyLanguage.bengali),
      ('ami tomake bhalobashi', ReplyLanguage.bengali),
      ('ami AI niye jante chai', ReplyLanguage.bengali),
      ('x^2 er derivative ki?', ReplyLanguage.bengali),
      ('Tell me about Dhaka', ReplyLanguage.english),
    ]) {
      test(text, () => expect(ReplyLanguage.detect(text), expected));
    }

    test('text without words has no language', () {
      expect(ReplyLanguage.detect('42 + 7 = ?'), isNull);
      expect(ReplyLanguage.detect('👍'), isNull);
      expect(ReplyLanguage.detect(''), isNull);
    });
  });

  test('the newest message with words decides', () {
    expect(
      ReplyLanguage.forConversation(['তুমি কেমন আছো?', 'What is AI?']),
      ReplyLanguage.english,
    );
    expect(
      ReplyLanguage.forConversation(['What is AI?', 'kemon acho']),
      ReplyLanguage.bengali,
    );
    expect(
      ReplyLanguage.forConversation(['তুমি কেমন আছো?', '12 * 12']),
      ReplyLanguage.bengali,
    );
    expect(ReplyLanguage.forConversation(['😀']), isNull);
    expect(ReplyLanguage.forConversation([]), isNull);
  });

  test('the instruction follows the system prompt', () {
    expect(
      ReplyLanguage.english.appendTo(' Be kind. '),
      'Be kind.\n\n${ReplyLanguage.english.instruction}',
    );
    expect(
      ReplyLanguage.bengali.appendTo(''),
      ReplyLanguage.bengali.instruction,
    );
  });
}
