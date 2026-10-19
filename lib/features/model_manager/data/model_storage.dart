import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// Layout of model files in app private storage.
///
/// ```text
/// <app support>/models/<id>.gguf          installed models
/// <app support>/models/.partial/<id>.part  downloads in progress
/// <app support>/models/registry.json       installed model records
/// ```
///
/// App support is private to the app (Android `files/`, iOS
/// `Library/Application Support`). Android backup rules exclude it; on iOS
/// the models directory is flagged as excluded from iCloud backup.
final class ModelStorage {
  /// Creates the layout under [supportDirectory].
  new(Directory supportDirectory)
    : modelsDirectory = Directory('${supportDirectory.path}/models');

  /// Where installed models live.
  final Directory modelsDirectory;

  /// Directory relative to app support, as the downloader expects.
  static const String partialRelativeDirectory = 'models/.partial';

  /// Where downloads are written before verification.
  Directory get partialDirectory =>
      Directory('${modelsDirectory.path}/.partial');

  /// The registry file.
  File get registryFile => File('${modelsDirectory.path}/registry.json');

  /// The pending downloads file.
  File get pendingFile => File('${modelsDirectory.path}/pending.json');

  /// Installed file for [fileName].
  File modelFile(String fileName) => File('${modelsDirectory.path}/$fileName');

  /// Partial download file name for model [id].
  static String partialFileName(String id) => '$id.part';

  /// Partial download file for model [id].
  File partialFile(String id) =>
      File('${partialDirectory.path}/${partialFileName(id)}');

  /// Creates the directories.
  Future<void> ensureCreated() async {
    await partialDirectory.create(recursive: true);
  }
}

/// Lowercase hex SHA-256 of the file at [path], computed in a background
/// isolate in 4 MB chunks so multi-gigabyte models never block the UI or
/// fill memory.
Future<String> sha256OfFile(String path) => Isolate.run(() {
  final input = File(path).openSync();
  try {
    final output = _DigestSink();
    final sink = sha256.startChunkedConversion(output);
    while (true) {
      final chunk = input.readSync(4 * 1024 * 1024);
      if (chunk.isEmpty) break;
      sink.add(chunk);
    }
    sink.close();
    return output.value.toString();
  } finally {
    input.closeSync();
  }
});

final class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
