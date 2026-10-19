import 'package:emberwit/features/chat/data/platform_voice_input.dart';
import 'package:emberwit/features/chat/domain/voice_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('test/voice');
  const events = EventChannel('test/voice/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final voice = PlatformVoiceInput(methods: methods, events: events);

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(methods, null));

  test('starts with the language tags and maps native errors', () async {
    answer((_) => 'en-US');
    expect(await voice.start(VoiceLanguage.english), isNull);
    expect(calls.single.arguments, {
      'tags': ['en-US', 'en-GB', 'en-IN'],
    });
    for (final (code, problem) in [
      ('permission', VoiceProblem.permissionDenied),
      ('not_installed', VoiceProblem.notInstalled),
      ('downloading', VoiceProblem.downloading),
      ('unsupported', VoiceProblem.unsupported),
      ('busy', VoiceProblem.busy),
      ('unavailable', VoiceProblem.unavailable),
      ('weird', VoiceProblem.failed),
    ]) {
      answer((_) => throw PlatformException(code: code));
      expect(await voice.start(VoiceLanguage.bengali), problem);
    }
  });

  test('a platform without the channel has no voice typing', () async {
    expect(await voice.isAvailable(), isFalse);
    expect(await voice.start(VoiceLanguage.english), VoiceProblem.unavailable);
    expect(await voice.install(VoiceLanguage.english), isFalse);
    await voice.stop();
    await voice.cancel();
  });

  test('availability, stop, cancel and install reach the host', () async {
    answer(
      (call) => call.method == 'stop' || call.method == 'cancel' ? null : true,
    );
    expect(await voice.isAvailable(), isTrue);
    await voice.stop();
    await voice.cancel();
    expect(await voice.install(VoiceLanguage.bengali), isTrue);
    expect(calls.map((c) => c.method), [
      'isAvailable',
      'stop',
      'cancel',
      'install',
    ]);
  });

  test('decodes recognizer events', () async {
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          sink
            ..success({'type': 'ready'})
            ..success({'type': 'level', 'value': 4.0})
            ..success({'type': 'level', 'value': 50.0})
            ..success({'type': 'partial', 'text': 'kemon'})
            ..success({'type': 'unknown'})
            ..success({'type': 'final', 'text': 'kemon acho'})
            ..success({'type': 'error', 'code': 'no_speech'})
            ..endOfStream();
        },
      ),
    );
    final got = await voice.events.toList();
    expect(got[0], isA<VoiceReady>());
    expect((got[1] as VoiceLevel).level, closeTo(0.5, 1e-9));
    expect((got[2] as VoiceLevel).level, 1);
    expect((got[3] as VoiceText).text, 'kemon');
    expect((got[3] as VoiceText).isFinal, isFalse);
    expect((got[4] as VoiceText).isFinal, isTrue);
    expect((got[5] as VoiceFailed).problem, VoiceProblem.noSpeech);
    expect(got, hasLength(6));
  });
}
