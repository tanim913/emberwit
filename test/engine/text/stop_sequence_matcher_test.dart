import 'package:emberwit/engine/text/stop_sequence_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

String _run(StopSequenceMatcher matcher, List<String> pieces) {
  final out = StringBuffer();
  for (final piece in pieces) {
    final result = matcher.add(piece);
    out.write(result.emit);
    if (result.stopped) return out.toString();
  }
  return (out..write(matcher.flush())).toString();
}

void main() {
  group('StopSequenceMatcher', () {
    test('passes text through without stop sequences', () {
      final matcher = StopSequenceMatcher(const []);
      expect(matcher.add('abc'), (emit: 'abc', stopped: false));
      expect(matcher.flush(), '');
    });

    test('stops at a sequence inside one piece and drops it', () {
      final matcher = StopSequenceMatcher(const ['<|end|>']);
      expect(_run(matcher, ['Hi<|end|>more']), 'Hi');
      expect(matcher.stopped, isTrue);
    });

    test('stops at a sequence split across pieces', () {
      final matcher = StopSequenceMatcher(const ['<|end|>']);
      expect(_run(matcher, ['Hello', ' <|', 'en', 'd|>', 'x']), 'Hello ');
    });

    test('releases held text that turns out not to be a stop', () {
      final matcher = StopSequenceMatcher(const ['<|end|>']);
      final first = matcher.add('a <|e');
      expect(first.emit, 'a ');
      final second = matcher.add('xtra');
      expect(second, (emit: '<|extra', stopped: false));
    });

    test('flushes held text at the end', () {
      final matcher = StopSequenceMatcher(const ['User:']);
      expect(_run(matcher, ['Bye. Us']), 'Bye. Us');
    });

    test('uses the earliest of several sequences', () {
      final matcher = StopSequenceMatcher(const ['###', '\nUser:']);
      expect(_run(matcher, ['one\nUser: two ### three']), 'one');
    });

    test('ignores empty sequences and input after stopping', () {
      final matcher = StopSequenceMatcher(const ['', 'X']);
      expect(matcher.add('aXb'), (emit: 'a', stopped: true));
      expect(matcher.add('more'), (emit: '', stopped: true));
      expect(matcher.flush(), '');
    });

    test('works with Bengali text', () {
      final matcher = StopSequenceMatcher(const ['ব্যবহারকারী:']);
      expect(_run(matcher, ['ধন্যবাদ। ব্যব', 'হারকারী: আর']), 'ধন্যবাদ। ');
    });
  });
}
