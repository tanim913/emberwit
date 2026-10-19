import 'package:flutter_test/flutter_test.dart';
import 'package:llama_ffi/llama_ffi.dart';

void main() {
  group('backendDirectoryFromMaps', () {
    test('finds the directory of an extracted libllama.so', () {
      const maps = '''
7f0000-7f1000 r--p 00000000 fd:00 1 /system/lib64/libc.so
7f2000-7f3000 r-xp 00000000 fd:00 2 /data/app/~~x==/app.emberwit.dev-y==/lib/arm64/libllama.so
''';
      expect(
        backendDirectoryFromMaps(maps),
        '/data/app/~~x==/app.emberwit.dev-y==/lib/arm64',
      );
    });

    test('accepts versioned sonames on Linux', () {
      const maps = '7f r-xp 0 fd:00 3 /opt/app/lib/libllama.so.0.5.0\n';
      expect(backendDirectoryFromMaps(maps), '/opt/app/lib');
    });

    test('returns null when loaded from inside an APK', () {
      const maps =
          '7f r-xp 0 fd:00 3 /data/app/base.apk!/lib/arm64-v8a/libllama.so\n';
      expect(backendDirectoryFromMaps(maps), isNull);
    });

    test('returns null when not mapped', () {
      expect(backendDirectoryFromMaps('7f r-xp 0 0 0 /lib/libc.so\n'), isNull);
      expect(backendDirectoryFromMaps(''), isNull);
    });
  });

  test('LlamaException describes its code', () {
    expect(
      const LlamaException(LlamaErrorCode.fileNotFound).toString(),
      'LlamaException(fileNotFound)',
    );
    expect(
      const LlamaException(LlamaErrorCode.decodeFailed, 'code 2').toString(),
      'LlamaException(decodeFailed: code 2)',
    );
  });
}
