import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:emberwit/core/catalog/model_catalog.dart';

import '../../tool/catalog/catalog_signing.dart';

/// A throwaway signing key for tests.
final class TestSigner {
  new _(this.seed, this.publicKey);

  /// Creates a fresh key.
  static Future<TestSigner> create() async {
    final pair = await Ed25519().newKeyPair();
    return TestSigner._(
      await pair.extractPrivateKeyBytes(),
      (await pair.extractPublicKey()).bytes,
    );
  }

  final List<int> seed;
  final List<int> publicKey;

  String get keyId => keyIdFor(publicKey);

  Map<String, String> get trustedKeys => {keyId: base64Encode(publicKey)};

  /// Signs [manifest] and returns envelope bytes.
  Future<Uint8List> sign(Map<String, dynamic> manifest) async {
    final envelope = await signEnvelope(
      utf8.encode(jsonEncode(manifest)),
      seed,
    );
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }
}

Map<String, dynamic> entryJson({
  String id = 'tiny-q4',
  List<String> urls = const [
    'https://example.org/tiny.gguf',
    'https://mirror.example.org/tiny.gguf',
  ],
  String sha =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  int size = 1000000,
  bool agreement = false,
  Map<String, dynamic> extra = const {},
}) => {
  'id': id,
  'displayName': 'Tiny',
  'family': 'llama',
  'parameterCount': 1000000,
  'quantization': 'Q4_K_M',
  'fileSizeBytes': size,
  'sha256': sha,
  'downloadUrls': urls,
  'recommendedContextLength': 2048,
  'kvCacheBytesPerToken': 1024,
  'languages': [
    {'code': 'en', 'quality': 'good'},
    {'code': 'bn', 'quality': 'basic'},
  ],
  'license': {
    'id': 'MIT',
    'name': 'MIT License',
    'url': 'https://example.org/license',
    'requiresAgreement': agreement,
  },
  'chatTemplate': 'chatml',
  'description': {'en': 'Tiny model', 'bn': 'ছোট মডেল'},
  ...extra,
};

Map<String, dynamic> manifestJson({
  int version = 2,
  int schema = 1,
  List<Map<String, dynamic>>? models,
}) => {
  'schemaVersion': schema,
  'catalogVersion': version,
  'generatedAt': '2026-09-24T00:00:00Z',
  'models': models ?? [entryJson()],
};

CatalogEntry entry({
  String id = 'tiny-q4',
  bool agreement = false,
  String sha =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  int size = 1000000,
}) => CatalogEntry.fromJson(
  entryJson(id: id, agreement: agreement, sha: sha, size: size),
);
