// Shared helpers for the catalog tools. Pure Dart: runs with `dart run`.
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// Format marker of the signed envelope.
const String envelopeFormat = 'emberwit.signed-catalog.v1';

/// Key id: first 8 bytes of SHA-256 of the raw public key, hex.
String keyIdFor(List<int> publicKey) =>
    crypto.sha256.convert(publicKey).toString().substring(0, 16);

/// Signs [payload] (the exact manifest bytes) with the Ed25519 [seed].
Future<Map<String, String>> signEnvelope(
  List<int> payload,
  List<int> seed,
) async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();
  final signature = await algorithm.sign(payload, keyPair: keyPair);
  return {
    'format': envelopeFormat,
    'keyId': keyIdFor(publicKey.bytes),
    'payload': base64Encode(payload),
    'signature': base64Encode(signature.bytes),
  };
}
