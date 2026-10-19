import 'package:emberwit/core/preferences/preference_keys.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:emberwit/features/chat/domain/voice_input.dart';
import 'package:emberwit/features/chat/presentation/chat_page.dart';
import 'package:emberwit/features/chat/presentation/voice_typing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_voice_input.dart';
import 'chat_harness.dart';

void main() {
  group('joinDictation', () {
    test('adds the heard words after the typed text', () {
      expect(joinDictation('', 'hello'), 'hello');
      expect(joinDictation('Tell me', 'a joke '), 'Tell me a joke');
      expect(joinDictation('Line\n', 'two'), 'Line\ntwo');
      expect(joinDictation('Kept', '  '), 'Kept');
    });
  });

  Future<(ChatHarness, FakeVoiceInput)> open(
    WidgetTester tester, {
    FakeVoiceInput? voice,
    Locale locale = const Locale('en'),
    Map<String, Object> values = const {},
  }) async {
    final fake = voice ?? FakeVoiceInput();
    final h = ChatHarness(voice: fake);
    late Conversation chat;
    await tester.runAsync(() async {
      chat = await h.repository.createConversation(title: 'T');
    });
    await h.pump(
      tester,
      ChatPage(conversationId: chat.id),
      locale: locale,
      values: values,
    );
    return (h, fake);
  }

  Finder field() => find.byKey(const Key('chat-input'));
  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(field()).controller!.text;

  testWidgets('no microphone without an offline recognizer', (tester) async {
    final (h, _) = await open(tester, voice: FakeVoiceInput(available: false));
    expect(find.byKey(const Key('chat-voice')), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('dictates after the typed text, live, then stops', (
    tester,
  ) async {
    final (h, voice) = await open(tester);
    await tester.enterText(field(), 'Tell me');
    await tester.tap(find.byKey(const Key('chat-voice')));
    await h.settle(tester);
    expect(voice.started, [VoiceLanguage.english]);
    // Until the microphone is open, the bar says so.
    expect(find.text('Getting ready…'), findsOneWidget);
    voice.emit(const VoiceReady());
    await h.settle(tester);
    expect(find.text('Listening…'), findsOneWidget);
    expect(find.byKey(const Key('chat-voice-language')), findsOneWidget);

    voice
      ..emit(const VoiceLevel(0.8))
      ..emit(const VoiceText('a', isFinal: false));
    await h.settle(tester);
    expect(fieldText(tester), 'Tell me a');
    voice.emit(const VoiceText('a joke', isFinal: true));
    await h.settle(tester);
    expect(fieldText(tester), 'Tell me a joke');
    expect(find.byKey(const Key('chat-voice-language')), findsNothing);

    // Typing more and dictating again appends again.
    await tester.tap(find.byKey(const Key('chat-voice')));
    await h.settle(tester);
    await tester.tap(find.byKey(const Key('chat-voice')));
    await h.settle(tester);
    expect(voice.stops, 1);
    await h.dispose(tester);
  });

  testWidgets('switching language restarts and is remembered', (tester) async {
    final (h, voice) = await open(tester);
    await tester.tap(find.byKey(const Key('chat-voice')));
    await h.settle(tester);
    voice.emit(const VoiceText('ami', isFinal: false));
    await h.settle(tester);
    await tester.tap(find.byKey(const Key('chat-voice-language')));
    await h.settle(tester);
    expect(voice.cancels, 1);
    expect(voice.started, [VoiceLanguage.english, VoiceLanguage.bengali]);
    expect(fieldText(tester), '', reason: 'the old language text is dropped');
    expect(find.text('বাংলা'), findsOneWidget);
    await h.dispose(tester);

    final (h2, voice2) = await open(
      tester,
      values: {PreferenceKeys.voiceLanguage: 'bengali'},
    );
    await tester.tap(find.byKey(const Key('chat-voice')));
    await h2.settle(tester);
    expect(voice2.started, [VoiceLanguage.bengali]);
    await h2.dispose(tester);
  });

  testWidgets('opened from the widget, listens once unlocked', (tester) async {
    final voice = FakeVoiceInput();
    final h = ChatHarness(voice: voice);
    late Conversation chat;
    await tester.runAsync(() async {
      chat = await h.repository.createConversation(title: 'T');
    });
    final locked = ValueNotifier(true);
    await h.pump(
      tester,
      ValueListenableBuilder(
        valueListenable: locked,
        builder: (_, isLocked, _) => TickerMode(
          enabled: !isLocked,
          child: ChatPage(conversationId: chat.id, startVoice: true),
        ),
      ),
    );
    expect(voice.started, isEmpty, reason: 'never listens behind the lock');
    locked.value = false;
    await h.settle(tester);
    expect(voice.started, [VoiceLanguage.english]);
    await h.dispose(tester);
    locked.dispose();
  });

  testWidgets('listens in Bengali when the app is in Bengali', (tester) async {
    final (h, voice) = await open(tester, locale: const Locale('bn'));
    await tester.tap(find.byKey(const Key('chat-voice')));
    await h.settle(tester);
    expect(voice.started, [VoiceLanguage.bengali]);
    await h.dispose(tester);
  });

  testWidgets('a missing language pack can be downloaded', (tester) async {
    final voice = FakeVoiceInput()..startProblem = VoiceProblem.notInstalled;
    final (h, _) = await open(tester, voice: voice);
    await tester.tap(find.byKey(const Key('chat-voice')));
    await h.settle(tester);
    expect(
      find.text('Offline English voice typing is not on this phone yet.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('chat-voice-language')), findsNothing);
    await tester.tap(find.text('Download'));
    await h.settle(tester);
    expect(voice.installed, [VoiceLanguage.english]);
    await tester.pumpAndSettle();
    expect(find.textContaining("Follow your phone's prompt"), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('errors are explained; silence after words is not', (
    tester,
  ) async {
    final (h, voice) = await open(tester);
    await tester.tap(find.byKey(const Key('chat-voice')));
    await h.settle(tester);
    // The first silence (the recognizer was still starting) just listens
    // again; only a second one is reported.
    voice.emit(const VoiceFailed(VoiceProblem.noSpeech));
    await h.settle(tester);
    expect(find.textContaining("Didn't catch that"), findsNothing);
    expect(voice.started, [VoiceLanguage.english, VoiceLanguage.english]);
    expect(find.text('Getting ready…'), findsOneWidget);
    voice.emit(const VoiceFailed(VoiceProblem.noSpeech));
    await h.settle(tester);
    expect(find.textContaining("Didn't catch that"), findsOneWidget);
    expect(voice.started, hasLength(2));

    ScaffoldMessenger.of(tester.element(field())).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-voice')));
    await h.settle(tester);
    voice
      ..emit(const VoiceText('hello', isFinal: false))
      ..emit(const VoiceFailed(VoiceProblem.noSpeech));
    await h.settle(tester);
    expect(find.textContaining("Didn't catch that"), findsNothing);
    expect(fieldText(tester), 'hello');
    await h.dispose(tester);
  });

  testWidgets('a language the phone lacks falls back to English', (
    tester,
  ) async {
    // Bengali chosen earlier, but this phone cannot recognize it offline.
    final voice = FakeVoiceInput()..startProblem = VoiceProblem.unsupported;
    final (h, _) = await open(
      tester,
      voice: voice,
      values: {PreferenceKeys.voiceLanguage: 'bengali'},
    );
    await tester.tap(find.byKey(const Key('chat-voice')));
    await h.settle(tester);
    expect(voice.started, [VoiceLanguage.bengali]);
    expect(
      find.textContaining('cannot recognize বাংলা offline'),
      findsOneWidget,
    );
    expect(find.textContaining('back to English'), findsOneWidget);
    // The next tap listens in English: not stuck on Bengali.
    voice.startProblem = null;
    await tester.tap(find.byKey(const Key('chat-voice')));
    await h.settle(tester);
    expect(voice.started.last, VoiceLanguage.english);
    await h.dispose(tester);
  });

  testWidgets('holding the microphone changes the language', (tester) async {
    final (h, voice) = await open(tester);
    await tester.longPress(find.byKey(const Key('chat-voice')));
    await h.settle(tester);
    expect(voice.started, isEmpty, reason: 'holding does not listen');
    expect(find.textContaining('now listens in বাংলা'), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat-voice')));
    await h.settle(tester);
    expect(voice.started, [VoiceLanguage.bengali]);
    await h.dispose(tester);
  });

  testWidgets('sending while listening sends the field and stops', (
    tester,
  ) async {
    final (h, voice) = await open(tester);
    await tester.tap(find.byKey(const Key('chat-voice')));
    await h.settle(tester);
    voice.emit(const VoiceText('What is AI', isFinal: false));
    await h.settle(tester);
    await tester.tap(find.byKey(const Key('chat-send')));
    await h.settle(tester);
    expect(voice.cancels, 1);
    expect(fieldText(tester), '');
    expect(find.text('What is AI'), findsWidgets, reason: 'sent');
    voice.emit(const VoiceText('What is AI now', isFinal: true));
    await h.settle(tester);
    expect(fieldText(tester), '', reason: 'late text is ignored');
    await h.dispose(tester);
  });
}
