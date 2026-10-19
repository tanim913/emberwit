import 'dart:typed_data';

import 'package:emberwit/core/chat/chat_archive.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/features/settings/data/archive_files.dart';

/// In-memory [ChatArchive]: an "export" is the passphrase's bytes, and
/// importing checks it.
class FakeChatArchive implements ChatArchive {
  new({this.count = 3});

  int count;
  final List<String> calls = [];

  @override
  Future<int> conversationCount() async => count;

  @override
  Future<void> deleteAll() async {
    calls.add('deleteAll');
    count = 0;
  }

  @override
  Future<Result<Uint8List>> export(String passphrase) async {
    calls.add('export');
    if (passphrase.length < 8) {
      return const Err(ArchiveFailure(ArchiveFailureReason.weakPassphrase));
    }
    return Ok(Uint8List.fromList(passphrase.codeUnits));
  }

  @override
  Future<Result<int>> import(Uint8List bytes, String passphrase) async {
    calls.add('import');
    if (String.fromCharCodes(bytes) != passphrase) {
      return const Err(ArchiveFailure(ArchiveFailureReason.wrongPassphrase));
    }
    return const Ok(2);
  }
}

/// [ArchiveFiles] that keeps saved files in memory.
class FakeArchiveFiles implements ArchiveFiles {
  new({this.toOpen, this.cancelSave = false});

  Uint8List? toOpen;
  bool cancelSave;
  final Map<String, Uint8List> saved = {};

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    if (cancelSave) return false;
    saved[fileName] = bytes;
    return true;
  }

  @override
  Future<Uint8List?> open() async => toOpen;
}
