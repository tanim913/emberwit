import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llama_ffi/src/gguf.dart';

Uint8List _header({int version = 3, List<int> magic = const [71, 71, 85, 70]}) {
  final data = ByteData(24);
  for (var i = 0; i < 4; i++) {
    data.setUint8(i, magic[i]);
  }
  data
    ..setUint32(4, version, Endian.little)
    ..setUint64(8, 291, Endian.little)
    ..setUint64(16, 24, Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  group('parseGgufHeader', () {
    test('reads version and counts', () {
      final header = parseGgufHeader(_header())!;
      expect(header.version, 3);
      expect(header.tensorCount, 291);
      expect(header.metadataCount, 24);
      expect(header.isSupportedVersion, isTrue);
    });

    test('flags unsupported versions', () {
      expect(parseGgufHeader(_header(version: 1))!.isSupportedVersion, isFalse);
      expect(parseGgufHeader(_header(version: 2))!.isSupportedVersion, isTrue);
    });

    test('rejects wrong magic and short input', () {
      expect(parseGgufHeader(_header(magic: [80, 75, 3, 4])), isNull);
      expect(parseGgufHeader(Uint8List(10)), isNull);
    });
  });

  group('readGgufHeader', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('gguf'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads a file header', () {
      final file = File('${dir.path}/m.gguf')
        ..writeAsBytesSync([..._header(), ...List.filled(100, 0)]);
      expect(readGgufHeader(file)?.version, 3);
    });

    test('returns null for missing, short or foreign files', () {
      expect(readGgufHeader(File('${dir.path}/missing.gguf')), isNull);
      final short = File('${dir.path}/short')..writeAsBytesSync([71, 71]);
      expect(readGgufHeader(short), isNull);
      final zip = File('${dir.path}/zip')
        ..writeAsBytesSync(_header(magic: [80, 75, 3, 4]));
      expect(readGgufHeader(zip), isNull);
    });
  });
}
