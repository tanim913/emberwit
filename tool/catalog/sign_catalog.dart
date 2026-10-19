// Signs a catalog manifest with the Ed25519 catalog key.
//
// Usage: dart run tool/catalog/sign_catalog.dart <manifest.json> <private-key-file> <out.signed.json>
//
// The envelope carries the manifest bytes base64 encoded, so the signature
// covers exactly what the app parses, independent of JSON formatting.
import 'dart:convert';
import 'dart:io';

import 'catalog_signing.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln(
      'usage: dart run tool/catalog/sign_catalog.dart '
      '<manifest.json> <private-key-file> <out.signed.json>',
    );
    exit(64);
  }
  final payload = File(args[0]).readAsBytesSync();
  final manifest = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
  if (manifest['schemaVersion'] is! int || manifest['catalogVersion'] is! int) {
    stderr.writeln('manifest needs integer schemaVersion and catalogVersion');
    exit(65);
  }
  final seed = base64Decode(File(args[1]).readAsStringSync().trim());
  final envelope = await signEnvelope(payload, seed);
  File(args[2])
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(envelope));
  stdout
    ..writeln('Signed ${args[0]} with key ${envelope['keyId']}')
    ..writeln('Wrote ${args[2]}');
}
