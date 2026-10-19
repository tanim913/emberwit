import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/features/model_catalog/data/catalog_trust.dart';
import 'package:emberwit/features/model_catalog/data/signed_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/catalog_fixtures.dart';

void main() {
  late TestSigner signer;
  late SignedCatalogVerifier verifier;

  setUpAll(() async {
    signer = await TestSigner.create();
    verifier = SignedCatalogVerifier(signer.trustedKeys);
  });

  test('the bundled catalog verifies with the shipped public key', () async {
    final bytes = File(bundledCatalogAsset).readAsBytesSync();
    final result = await SignedCatalogVerifier(trustedCatalogKeys)
        .verify(bytes);
    final catalog = result.valueOrNull!;
    expect(catalog.models, hasLength(8));
    expect(catalog.models.map((m) => m.family).toSet(), {
      'qwen3',
      'gemma3',
      'llama3.2',
      'phi4',
    });
    for (final model in catalog.models) {
      expect(model.quantization, 'Q4_K_M');
      expect(model.downloadUrls.length, greaterThanOrEqualTo(2));
      expect(model.description['en'], isNotEmpty);
      expect(model.description['bn'], isNotEmpty);
      expect(model.kvCacheBytesPerToken, isNotNull);
    }
    final gemma = catalog.entry('gemma3-1b-q4_k_m')!;
    expect(gemma.license.requiresAgreement, isTrue);
  });

  test('accepts a validly signed catalog', () async {
    final result = await verifier.verify(await signer.sign(manifestJson()));
    expect(result.valueOrNull!.catalogVersion, 2);
    expect(result.valueOrNull!.models.single.id, 'tiny-q4');
  });

  test('rejects a tampered payload', () async {
    final envelope = jsonDecode(
      utf8.decode(await signer.sign(manifestJson())),
    ) as Map<String, dynamic>;
    final tampered = utf8.encode(
      jsonEncode(manifestJson()..['catalogVersion'] = 99),
    );
    envelope['payload'] = base64Encode(tampered);
    final result = await verifier.verify(
      Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
    );
    expect(
      result.failureOrNull,
      const CatalogFailure(CatalogFailureReason.invalidSignature),
    );
  });

  test('rejects an unknown key and a malformed signature', () async {
    final other = await TestSigner.create();
    final foreign = await other.sign(manifestJson());
    expect(
      (await verifier.verify(foreign)).failureOrNull,
      const CatalogFailure(CatalogFailureReason.invalidSignature),
    );

    final envelope = jsonDecode(
      utf8.decode(await signer.sign(manifestJson())),
    ) as Map<String, dynamic>;
    envelope['signature'] = base64Encode([1, 2, 3]);
    expect(
      (await verifier.verify(
        Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
      )).failureOrNull,
      const CatalogFailure(CatalogFailureReason.invalidSignature),
    );
  });

  test('rejects malformed envelopes and unknown formats', () async {
    expect(
      (await verifier.verify(Uint8List.fromList(utf8.encode('nope'))))
          .failureOrNull,
      const CatalogFailure(CatalogFailureReason.malformed),
    );
    final envelope = jsonDecode(
      utf8.decode(await signer.sign(manifestJson())),
    ) as Map<String, dynamic>;
    envelope['format'] = 'emberwit.signed-catalog.v9';
    expect(
      (await verifier.verify(
        Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
      )).failureOrNull,
      const CatalogFailure(CatalogFailureReason.unsupportedSchema),
    );
  });

  group('parseCatalog', () {
    Uint8List bytes(Object json) =>
        Uint8List.fromList(utf8.encode(jsonEncode(json)));

    test('ignores unknown fields and unknown enum values', () {
      final json = manifestJson(
        models: [
          entryJson(
            extra: {
              'futureField': {'x': 1},
              'languages': [
                {'code': 'bn', 'quality': 'excellent'},
              ],
            },
          ),
        ],
      )..['alsoNew'] = true;
      final catalog = parseCatalog(bytes(json)).valueOrNull!;
      expect(catalog.models.single.qualityFor('bn'), LanguageQuality.unknown);
    });

    test('rejects a newer schema version', () {
      expect(
        parseCatalog(bytes(manifestJson(schema: 2))).failureOrNull,
        const CatalogFailure(CatalogFailureReason.unsupportedSchema),
      );
    });

    test('rejects missing required top level fields', () {
      expect(
        parseCatalog(bytes({'models': <Object>[]})).failureOrNull,
        const CatalogFailure(CatalogFailureReason.malformed),
      );
      expect(
        parseCatalog(bytes({'schemaVersion': 1, 'models': <Object>[]}))
            .failureOrNull,
        const CatalogFailure(CatalogFailureReason.malformed),
      );
      expect(
        parseCatalog(Uint8List.fromList([0xff])).failureOrNull,
        const CatalogFailure(CatalogFailureReason.malformed),
      );
    });

    test('skips invalid entries and keeps valid ones', () {
      final catalog = parseCatalog(
        bytes(
          manifestJson(
            models: [
              entryJson(id: 'ok'),
              entryJson(id: 'http', urls: ['http://example.org/x.gguf']),
              entryJson(id: 'badsha', sha: 'xyz'),
              entryJson(id: 'empty', size: 0),
              entryJson(id: '../escape'),
              {'id': 'incomplete'},
            ],
          ),
        ),
      ).valueOrNull!;
      expect(catalog.models.map((m) => m.id), ['ok']);
    });

    test('drops non HTTPS mirrors but keeps HTTPS ones', () {
      final catalog = parseCatalog(
        bytes(
          manifestJson(
            models: [
              entryJson(urls: ['http://a.org/x.gguf', 'https://b.org/x.gguf']),
            ],
          ),
        ),
      ).valueOrNull!;
      expect(catalog.models.single.downloadUrls, ['https://b.org/x.gguf']);
    });
  });
}
