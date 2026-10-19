import 'dart:convert';

/// Decodes UTF-8 bytes that arrive in arbitrary chunks.
///
/// Model tokens are byte sequences and one character can be split across
/// several tokens. Bengali characters are three bytes each and are often
/// split. This decoder holds incomplete sequences back until the rest
/// arrives. Invalid bytes become U+FFFD instead of throwing.
final class Utf8StreamDecoder {
  /// Creates a decoder.
  new() {
    _sink = const Utf8Decoder(allowMalformed: true)
        .startChunkedConversion(StringConversionSink.fromStringSink(_buffer));
  }

  final StringBuffer _buffer = StringBuffer();
  late final ByteConversionSink _sink;

  /// Adds [bytes] and returns every character they complete.
  String add(List<int> bytes) {
    _sink.add(bytes);
    return _take();
  }

  /// Ends the stream and returns anything left, with an incomplete trailing
  /// sequence replaced by U+FFFD.
  String close() {
    _sink.close();
    return _take();
  }

  String _take() {
    final text = _buffer.toString();
    _buffer.clear();
    return text;
  }
}
