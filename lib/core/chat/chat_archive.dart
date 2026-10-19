import 'dart:typed_data';

import 'package:emberwit/core/result/result.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_archive.g.dart';

/// Bulk operations on all conversations, used by settings. Implemented by
/// the chat feature and wired in `featureBindings()`.
abstract interface class ChatArchive {
  /// Number of conversations stored.
  Future<int> conversationCount();

  /// Deletes every conversation and message.
  Future<void> deleteAll();

  /// Every conversation, encrypted with a key derived from [passphrase].
  /// The result is safe to store anywhere: without the passphrase it reveals
  /// nothing but its size.
  Future<Result<Uint8List>> export(String passphrase);

  /// Adds the conversations in an [export] file. Conversations already on
  /// the device are kept as they are. Returns how many were added.
  Future<Result<int>> import(Uint8List bytes, String passphrase);
}

/// The chat archive. Overridden by `featureBindings()`.
@Riverpod(keepAlive: true)
ChatArchive chatArchive(Ref ref) => throw StateError(
  'chatArchiveProvider must be overridden by featureBindings().',
);
