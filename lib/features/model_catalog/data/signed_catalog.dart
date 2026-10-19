import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';

/// Format marker of the signed catalog envelope.
const String signedCatalogFormat = 'emberwit.signed-catalog.v1';

/// Verifies and parses signed catalog envelopes:
///
/// ```json
/// {"format": "emberwit.signed-catalog.v1", "keyId": "...",
///  "payload": "<base64 manifest bytes>", "signature": "<base64 Ed25519>"}
/// ```
///
/// The signature covers the exact payload bytes. The payload is parsed only
/// after the signature verifies, so an attacker cannot reach the JSON parser
/// with unsigned input.
final class SignedCatalogVerifier {
  /// Creates a verifier trusting [trustedKeys] (key id to base64 public key).
  new(this.trustedKeys);

  /// Trusted Ed25519 public keys.
  final Map<String, String> trustedKeys;

  final Ed25519 _ed25519 = Ed25519();

  /// Verifies [envelopeBytes] and returns the catalog.
  Future<Result<ModelCatalog>> verify(Uint8List envelopeBytes) async {
    final Map<String, dynamic> envelope;
    final Uint8List payload;
    final List<int> signature;
    final String keyId;
    try {
      envelope = jsonDecode(utf8.decode(envelopeBytes)) as Map<String, dynamic>;
      if (envelope['format'] != signedCatalogFormat) {
        return const Err(
          CatalogFailure(CatalogFailureReason.unsupportedSchema),
        );
      }
      keyId = envelope['keyId'] as String;
      payload = base64Decode(envelope['payload'] as String);
      signature = base64Decode(envelope['signature'] as String);
    } on Object catch (error) {
      return Err(CatalogFailure(CatalogFailureReason.malformed, cause: error));
    }

    final key = trustedKeys[keyId];
    if (key == null || signature.length != 64) {
      return const Err(CatalogFailure(CatalogFailureReason.invalidSignature));
    }
    final valid = await _ed25519.verify(
      payload,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(
          base64Decode(key),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) {
      return const Err(CatalogFailure(CatalogFailureReason.invalidSignature));
    }
    return parseCatalog(payload);
  }
}

/// Parses verified manifest bytes.
///
/// A newer schema version is rejected. Unknown fields are ignored. An entry
/// that is invalid (missing fields, non HTTPS URL, bad hash) is skipped
/// rather than failing the whole catalog.
Result<ModelCatalog> parseCatalog(Uint8List payload) {
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
  } on Object catch (error) {
    return Err(CatalogFailure(CatalogFailureReason.malformed, cause: error));
  }
  final schema = json['schemaVersion'];
  if (schema is! int) {
    return const Err(CatalogFailure(CatalogFailureReason.malformed));
  }
  if (schema > supportedCatalogSchemaVersion) {
    return const Err(CatalogFailure(CatalogFailureReason.unsupportedSchema));
  }
  final entries = <CatalogEntry>[];
  for (final raw in json['models'] as List<dynamic>? ?? const []) {
    final entry = _parseEntry(raw);
    if (entry != null) entries.add(entry);
  }
  try {
    return Ok(
      ModelCatalog(
        schemaVersion: schema,
        catalogVersion: json['catalogVersion'] as int,
        generatedAt: DateTime.parse(json['generatedAt'] as String),
        models: entries,
      ),
    );
  } on Object catch (error) {
    return Err(CatalogFailure(CatalogFailureReason.malformed, cause: error));
  }
}

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

CatalogEntry? _parseEntry(Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  try {
    final entry = CatalogEntry.fromJson(raw);
    final urls = entry.downloadUrls
        .where((u) => Uri.tryParse(u)?.scheme == 'https')
        .toList();
    if (urls.isEmpty ||
        entry.fileSizeBytes <= 0 ||
        !_sha256Pattern.hasMatch(entry.sha256) ||
        !RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$').hasMatch(entry.id)) {
      return null;
    }
    return entry.copyWith(downloadUrls: urls);
  } on Object {
    return null;
  }
}
