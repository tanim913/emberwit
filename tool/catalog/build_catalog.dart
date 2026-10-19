// Builds the catalog manifest from tool/catalog/catalog_source.json.
//
// Usage: dart run tool/catalog/build_catalog.dart [source] [output]
//
// For every model it asks the Hugging Face API for the file's exact size and
// SHA-256 (the LFS object id), builds primary and mirror URLs pinned to the
// current commit, validates the result and writes the manifest JSON that
// sign_catalog.dart signs.
import 'dart:convert';
import 'dart:io';

const _schemaVersion = 1;
final _sha256 = RegExp(r'^[0-9a-f]{64}$');

Future<void> main(List<String> args) async {
  final source = File(
    args.isNotEmpty ? args[0] : 'tool/catalog/catalog_source.json',
  );
  final output = File(args.length > 1 ? args[1] : 'build/catalog/catalog.json');
  final spec = jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
  final mirrors = (spec['mirrorHosts'] as List<dynamic>? ?? []).cast<String>();
  final client = HttpClient()..userAgent = 'emberwit-catalog-builder';

  final models = <Map<String, dynamic>>[];
  for (final raw
      in (spec['models'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    final model = Map<String, dynamic>.of(raw);
    final hf = model.remove('huggingFace') as Map<String, dynamic>;
    final repo = hf['repo'] as String;
    final file = hf['file'] as String;
    final info = (await _getJson(
      client,
      'https://huggingface.co/api/models/$repo',
    )) as Map<String, dynamic>;
    final revision = info['sha'] as String;
    final tree = await _getJson(
      client,
      'https://huggingface.co/api/models/$repo/tree/$revision',
    );
    final entry = (tree as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere(
          (e) => e['path'] == file,
          orElse: () => throw StateError('$file not found in $repo'),
        );
    final size = entry['size'] as int;
    final sha = (entry['lfs'] as Map<String, dynamic>)['oid'] as String;
    if (!_sha256.hasMatch(sha)) throw StateError('bad sha for $file: $sha');
    if (info['gated'] != false && info['gated'] != null) {
      throw StateError(
        '$repo is gated; the app cannot download it anonymously',
      );
    }
    final path = '$repo/resolve/$revision/$file';
    model
      ..['fileSizeBytes'] = size
      ..['sha256'] = sha
      ..['downloadUrls'] = [
        'https://huggingface.co/$path',
        for (final host in mirrors) 'https://$host/$path',
      ];
    _validate(model);
    models.add(model);
    stdout.writeln(
      '${model['id']}: $size bytes, sha256 $sha @ ${revision.substring(0, 8)}',
    );
  }
  client.close();

  final manifest = {
    'schemaVersion': _schemaVersion,
    'catalogVersion': spec['catalogVersion'],
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'models': models,
  };
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );
  stdout.writeln('Wrote ${output.path} (${models.length} models)');
}

void _validate(Map<String, dynamic> m) {
  for (final key in [
    'id',
    'displayName',
    'family',
    'parameterCount',
    'quantization',
    'fileSizeBytes',
    'sha256',
    'downloadUrls',
    'license',
    'chatTemplate',
  ]) {
    if (m[key] == null) throw StateError('${m['id']}: missing $key');
  }
  for (final url in (m['downloadUrls'] as List<dynamic>).cast<String>()) {
    if (!url.startsWith('https://')) {
      throw StateError('${m['id']}: non HTTPS $url');
    }
  }
  final description = m['description'] as Map<String, dynamic>? ?? {};
  for (final lang in ['en', 'bn']) {
    if ((description[lang] as String? ?? '').isEmpty) {
      throw StateError('${m['id']}: missing $lang description');
    }
  }
}

Future<dynamic> _getJson(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();
  if (response.statusCode != 200) {
    throw HttpException('HTTP ${response.statusCode} for $url');
  }
  return jsonDecode(await response.transform(utf8.decoder).join());
}
