import 'dart:convert';

import 'package:emberwit/engine/text/utf8_stream_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Utf8StreamDecoder', () {
    test('passes ASCII through', () {
      final decoder = Utf8StreamDecoder();
      expect(decoder.add(utf8.encode('Hello ')), 'Hello ');
      expect(decoder.add(utf8.encode('world')), 'world');
      expect(decoder.close(), '');
    });

    test('joins Bengali characters split across tokens', () {
      const word = 'আমি বাংলায় কথা বলি';
      final bytes = utf8.encode(word);
      final decoder = Utf8StreamDecoder();
      final out = StringBuffer();
      // Worst case: one byte per token.
      for (final byte in bytes) {
        final piece = decoder.add([byte]);
        // Never emits half a character.
        expect(piece.contains('�'), isFalse);
        out.write(piece);
      }
      out.write(decoder.close());
      expect(out.toString(), word);
    });

    test('holds a partial sequence until completed', () {
      final bytes = utf8.encode('ক'); // 3 bytes
      final decoder = Utf8StreamDecoder();
      expect(decoder.add(bytes.sublist(0, 2)), '');
      expect(decoder.add(bytes.sublist(2)), 'ক');
    });

    test('replaces malformed and truncated bytes instead of throwing', () {
      final decoder = Utf8StreamDecoder();
      expect(decoder.add([0xFF, 0x41]), '�A');
      expect(decoder.add([0xE0, 0xA6]), '');
      expect(decoder.close(), '�');
    });

    test('handles emoji (4 byte sequences)', () {
      final bytes = utf8.encode('🔥ok');
      final decoder = Utf8StreamDecoder();
      expect(decoder.add(bytes.sublist(0, 3)), '');
      expect(decoder.add(bytes.sublist(3)), '🔥ok');
    });
  });
}
