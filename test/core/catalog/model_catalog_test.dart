import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/catalog_fixtures.dart';

void main() {
  test('entry helpers read languages, descriptions and specs', () {
    final e = entry();
    expect(e.qualityFor('bn'), LanguageQuality.basic);
    expect(e.qualityFor('fr'), LanguageQuality.unknown);
    expect(e.descriptionFor('bn'), 'ছোট মডেল');
    expect(e.descriptionFor('de'), 'Tiny model');
    final spec = e.toSpec(isInstalled: true);
    expect(spec.id, e.id);
    expect(spec.kvCacheBytesPerToken, 1024);
    expect(spec.isInstalled, isTrue);
    expect(CatalogEntry.fromJson(e.toJson()), e);
  });

  test('catalog finds entries by id', () {
    final catalog = ModelCatalog.fromJson(manifestJson());
    expect(catalog.entry('tiny-q4'), isNotNull);
    expect(catalog.entry('missing'), isNull);
  });
}
