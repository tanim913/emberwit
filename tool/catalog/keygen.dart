// Generates an Ed25519 key pair for signing the model catalog.
//
// Usage: dart run tool/catalog/keygen.dart <private-key-file>
//
// Writes the 32 byte seed (base64) to <private-key-file> with 0600
// permissions and prints the public key and key id to add to
// lib/features/model_catalog/data/catalog_trust.dart. Keep the private key
// offline and backed up; never commit it.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'catalog_signing.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'usage: dart run tool/catalog/keygen.dart <private-key-file>',
    );
    exit(64);
  }
  final file = File(args.single);
  if (file.existsSync()) {
    stderr.writeln('${file.path} exists; refusing to overwrite a signing key.');
    exit(1);
  }
  final keyPair = await Ed25519().newKeyPair();
  final seed = await keyPair.extractPrivateKeyBytes();
  final publicKey = (await keyPair.extractPublicKey()).bytes;
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(base64Encode(seed));
  if (!Platform.isWindows) {
    await Process.run('chmod', ['600', file.path]);
  }
  stdout
    ..writeln('Private key written to ${file.path}')
    ..writeln('Key id:     ${keyIdFor(publicKey)}')
    ..writeln('Public key: ${base64Encode(publicKey)}');
}
