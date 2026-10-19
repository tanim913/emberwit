import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:flutter/foundation.dart';

/// Argon2id cost of deriving the export key from a passphrase.
@immutable
final class ArchiveKdfParams {
  /// Creates parameters.
  const new({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// OWASP's minimum Argon2id configuration: 19 MiB, 2 passes, 1 lane.
  /// About a second on a mid range phone, which makes guessing a passphrase
  /// slow and memory hungry.
  static const ArchiveKdfParams standard = ArchiveKdfParams(
    memoryKiB: 19 * 1024,
    iterations: 2,
    parallelism: 1,
  );

  /// Memory in KiB.
  final int memoryKiB;

  /// Passes over memory.
  final int iterations;

  /// Lanes.
  final int parallelism;

  /// Whether a file's parameters are in a range this app accepts. Bounds
  /// stop a crafted file from demanding gigabytes of memory or hours of
  /// work before the passphrase is even checked.
  bool get isAcceptable =>
      memoryKiB >= 8 &&
      memoryKiB <= 64 * 1024 &&
      iterations >= 1 &&
      iterations <= 10 &&
      parallelism >= 1 &&
      parallelism <= 4;
}

/// A conversation and its messages, as stored in an export.
typedef ArchivedConversation = ({
  Conversation conversation,
  List<ChatMessage> messages,
});

/// Reads and writes encrypted chat export files.
///
/// File format (UTF-8 JSON):
///
/// ```json
/// {
///   "format": "emberwit.chat-export.v1",
///   "kdf": {"name": "argon2id", "memoryKiB": 19456, "iterations": 2,
///           "parallelism": 1, "salt": "<base64, 16 bytes>"},
///   "cipher": "aes-256-gcm",
///   "nonce": "<base64, 12 bytes>",
///   "ciphertext": "<base64>",
///   "mac": "<base64, 16 bytes>"
/// }
/// ```
///
/// The key is derived from the passphrase with Argon2id and a random salt;
/// the payload is encrypted with AES-256-GCM. The header (format and key
/// derivation parameters) is authenticated as associated data, so it cannot
/// be changed without the passphrase check failing. Nothing but sizes is
/// readable without the passphrase.
final class ChatArchiveCodec {
  /// Creates the codec. [kdf] is lowered in tests only.
  new({this.kdf = ArchiveKdfParams.standard, Random? random})
    : _random = random ?? Random.secure();

  /// Key derivation cost for new exports.
  final ArchiveKdfParams kdf;
  final Random _random;

  /// Format identifier of version 1 files.
  static const String format = 'emberwit.chat-export.v1';

  /// Shortest passphrase accepted for an export.
  static const int minPassphraseLength = 8;

  /// Payload schema version written by this app.
  static const int schemaVersion = 1;

  /// Encrypts [conversations] with [passphrase].
  Future<Result<Uint8List>> encode(
    List<ArchivedConversation> conversations,
    String passphrase, {
    DateTime? exportedAt,
  }) async {
    if (passphrase.length < minPassphraseLength) {
      return const Err(ArchiveFailure(ArchiveFailureReason.weakPassphrase));
    }
    final payload = utf8.encode(
      jsonEncode({
        'schemaVersion': schemaVersion,
        'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'conversations': [
          for (final c in conversations) _conversationToJson(c),
        ],
      }),
    );
    final salt = _bytes(16);
    final nonce = _bytes(12);
    final params = kdf;
    final aad = _associatedData(params, salt);
    final box = await Isolate.run(() async {
      final key = await _deriveKey(passphrase, salt, params);
      return await AesGcm.with256bits().encrypt(
        payload,
        secretKey: key,
        nonce: nonce,
        aad: aad,
      );
    });
    final envelope = {
      'format': format,
      'kdf': {
        'name': 'argon2id',
        'memoryKiB': params.memoryKiB,
        'iterations': params.iterations,
        'parallelism': params.parallelism,
        'salt': base64.encode(salt),
      },
      'cipher': 'aes-256-gcm',
      'nonce': base64.encode(box.nonce),
      'ciphertext': base64.encode(box.cipherText),
      'mac': base64.encode(box.mac.bytes),
    };
    return Ok(Uint8List.fromList(utf8.encode(jsonEncode(envelope))));
  }

  /// Decrypts an export file with [passphrase].
  Future<Result<List<ArchivedConversation>>> decode(
    Uint8List bytes,
    String passphrase,
  ) async {
    final _Envelope envelope;
    try {
      final parsed = _Envelope.parse(bytes);
      if (parsed == null) {
        return const Err(ArchiveFailure(ArchiveFailureReason.notAnArchive));
      }
      envelope = parsed;
    } on _UnsupportedVersion {
      return const Err(ArchiveFailure(ArchiveFailureReason.unsupportedVersion));
    }
    final List<int> clear;
    try {
      clear = await Isolate.run(() async {
        final key = await _deriveKey(
          passphrase,
          envelope.salt,
          envelope.params,
        );
        return await AesGcm.with256bits().decrypt(
          SecretBox(
            envelope.ciphertext,
            nonce: envelope.nonce,
            mac: Mac(envelope.mac),
          ),
          secretKey: key,
          aad: _associatedData(envelope.params, envelope.salt),
        );
      });
    } on SecretBoxAuthenticationError {
      return const Err(ArchiveFailure(ArchiveFailureReason.wrongPassphrase));
    }
    try {
      final json = jsonDecode(utf8.decode(clear));
      if (json is! Map<String, Object?>) throw const FormatException();
      final version = json['schemaVersion'];
      if (version is! int) throw const FormatException();
      if (version > schemaVersion) {
        return const Err(
          ArchiveFailure(ArchiveFailureReason.unsupportedVersion),
        );
      }
      final list = json['conversations'];
      if (list is! List<Object?>) throw const FormatException();
      return Ok([for (final c in list) _conversationFromJson(c)]);
    } on Object catch (e, s) {
      return Err(
        ArchiveFailure(
          ArchiveFailureReason.notAnArchive,
          cause: e,
          stackTrace: s,
        ),
      );
    }
  }

  Uint8List _bytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

  static List<int> _associatedData(ArchiveKdfParams p, List<int> salt) =>
      utf8.encode(
        '$format|argon2id|${p.memoryKiB}|${p.iterations}|${p.parallelism}|'
        '${base64.encode(salt)}',
      );

  static Future<SecretKey> _deriveKey(
    String passphrase,
    List<int> salt,
    ArchiveKdfParams p,
  ) => Argon2id(
    parallelism: p.parallelism,
    memory: p.memoryKiB,
    iterations: p.iterations,
    hashLength: 32,
  ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
}

final class _UnsupportedVersion implements Exception {
  const new();
}

final class _Envelope {
  const new({
    required this.params,
    required this.salt,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  final ArchiveKdfParams params;
  final List<int> salt;
  final List<int> nonce;
  final List<int> ciphertext;
  final List<int> mac;

  /// Parses the outer JSON; `null` when the file is not an export at all.
  static _Envelope? parse(Uint8List bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, Object?>) return null;
      final format = json['format'];
      if (format is! String) return null;
      if (format != ChatArchiveCodec.format) {
        if (format.startsWith('emberwit.chat-export.')) {
          throw const _UnsupportedVersion();
        }
        return null;
      }
      final kdf = json['kdf'];
      if (kdf is! Map<String, Object?> || kdf['name'] != 'argon2id') {
        return null;
      }
      if (json['cipher'] != 'aes-256-gcm') return null;
      final params = ArchiveKdfParams(
        memoryKiB: kdf['memoryKiB']! as int,
        iterations: kdf['iterations']! as int,
        parallelism: kdf['parallelism']! as int,
      );
      if (!params.isAcceptable) return null;
      final envelope = _Envelope(
        params: params,
        salt: base64.decode(kdf['salt']! as String),
        nonce: base64.decode(json['nonce']! as String),
        ciphertext: base64.decode(json['ciphertext']! as String),
        mac: base64.decode(json['mac']! as String),
      );
      if (envelope.salt.length < 16 ||
          envelope.nonce.length != 12 ||
          envelope.mac.length != 16) {
        return null;
      }
      return envelope;
    } on _UnsupportedVersion {
      rethrow;
    } on Object {
      return null;
    }
  }
}

Map<String, Object?> _conversationToJson(ArchivedConversation archived) {
  final c = archived.conversation;
  final s = c.settings;
  return {
    'id': c.id,
    'title': c.title,
    'pinned': c.pinned,
    'createdAt': c.createdAt.toUtc().toIso8601String(),
    'updatedAt': c.updatedAt.toUtc().toIso8601String(),
    'preview': c.preview,
    'settings': {
      'modelId': s.modelId,
      'systemPrompt': s.systemPrompt,
      'temperature': s.temperature,
      'topP': s.topP,
      'contextLength': s.contextLength,
      'maxTokens': s.maxTokens,
    },
    'messages': [
      for (final m in archived.messages)
        {
          'id': m.id,
          'role': m.role.name,
          'content': m.content,
          'createdAt': m.createdAt.toUtc().toIso8601String(),
          'status': m.status.name,
          'modelId': m.modelId,
          'droppedMessages': m.droppedMessages,
          if (m.stats case final stats?)
            'stats': {
              'promptTokens': stats.promptTokens,
              'generatedTokens': stats.generatedTokens,
              'timeToFirstTokenMs': stats.timeToFirstTokenMs,
              'tokensPerSecond': stats.tokensPerSecond,
            },
        },
    ],
  };
}

ArchivedConversation _conversationFromJson(Object? value) {
  final json = value! as Map<String, Object?>;
  final settings = json['settings']! as Map<String, Object?>;
  final id = json['id']! as String;
  final conversation = Conversation(
    id: id,
    title: json['title']! as String,
    pinned: json['pinned']! as bool,
    createdAt: DateTime.parse(json['createdAt']! as String).toLocal(),
    updatedAt: DateTime.parse(json['updatedAt']! as String).toLocal(),
    preview: json['preview']! as String,
    settings: ConversationSettings(
      modelId: settings['modelId'] as String?,
      systemPrompt: settings['systemPrompt']! as String,
      temperature: (settings['temperature']! as num).toDouble(),
      topP: (settings['topP']! as num).toDouble(),
      contextLength: settings['contextLength']! as int,
      maxTokens: settings['maxTokens']! as int,
    ),
  );
  final messages = [
    for (final raw in json['messages']! as List<Object?>)
      _messageFromJson(raw! as Map<String, Object?>, id),
  ];
  return (conversation: conversation, messages: messages);
}

ChatMessage _messageFromJson(Map<String, Object?> json, String conversation) {
  final stats = json['stats'] as Map<String, Object?>?;
  final status = MessageStatus.values.byName(json['status']! as String);
  return ChatMessage(
    id: json['id']! as String,
    conversationId: conversation,
    role: MessageRole.values.byName(json['role']! as String),
    content: json['content']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String).toLocal(),
    // A reply that was streaming when exported is restored as stopped.
    status: status == MessageStatus.streaming ? MessageStatus.stopped : status,
    modelId: json['modelId'] as String?,
    droppedMessages: json['droppedMessages']! as int,
    stats: stats == null
        ? null
        : MessageStats(
            promptTokens: stats['promptTokens']! as int,
            generatedTokens: stats['generatedTokens']! as int,
            timeToFirstTokenMs: stats['timeToFirstTokenMs']! as int,
            tokensPerSecond: (stats['tokensPerSecond']! as num).toDouble(),
          ),
  );
}
