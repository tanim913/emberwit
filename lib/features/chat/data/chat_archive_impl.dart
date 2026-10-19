import 'dart:typed_data';

import 'package:emberwit/core/chat/chat_archive.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/features/chat/data/chat_archive_codec.dart';
import 'package:emberwit/features/chat/domain/chat_repository.dart';

/// [ChatArchive] over the chat repository and [ChatArchiveCodec].
final class ChatArchiveImpl implements ChatArchive {
  /// Creates the archive.
  new(this._repository, {ChatArchiveCodec? codec})
    : _codec = codec ?? ChatArchiveCodec();

  final ChatRepository _repository;
  final ChatArchiveCodec _codec;

  @override
  Future<int> conversationCount() => _repository.conversationCount();

  @override
  Future<void> deleteAll() => _repository.deleteAll();

  @override
  Future<Result<Uint8List>> export(String passphrase) async {
    final conversations = await _repository.allConversations();
    return await _codec.encode([
      for (final c in conversations)
        (conversation: c, messages: await _repository.messages(c.id)),
    ], passphrase);
  }

  @override
  Future<Result<int>> import(Uint8List bytes, String passphrase) async {
    final decoded = await _codec.decode(bytes, passphrase);
    switch (decoded) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        var added = 0;
        for (final archived in value) {
          if (await _repository.restoreConversation(
            archived.conversation,
            archived.messages,
          )) {
            added++;
          }
        }
        return Ok(added);
    }
  }
}
