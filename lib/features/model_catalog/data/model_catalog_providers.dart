import 'dart:io';

import 'package:emberwit/core/catalog/catalog_repository.dart';
import 'package:emberwit/core/network/certificate_pins.dart';
import 'package:emberwit/core/network/secure_http_client.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/features/model_catalog/data/catalog_repository_impl.dart';
import 'package:emberwit/features/model_catalog/data/catalog_sources.dart';
import 'package:emberwit/features/model_catalog/data/catalog_trust.dart';
import 'package:emberwit/features/model_catalog/data/signed_catalog.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'model_catalog_providers.g.dart';

/// The model catalog feature's [CatalogRepository]; exposed through the
/// shared `catalogRepositoryProvider` by `featureBindings()`.
@Riverpod(keepAlive: true)
CatalogRepository modelCatalogRepository(Ref ref) {
  final config = ref.watch(flavorConfigProvider);
  final support = ref.watch(appSupportDirectoryProvider);
  final dio = createSecureDio(
    pinner: CertificatePinner({
      config.catalogUrl.host: config.catalogCertificatePins,
    }),
  );
  ref.onDispose(dio.close);
  return CatalogRepositoryImpl(
    verifier: SignedCatalogVerifier(trustedCatalogKeys),
    remote: DioCatalogRemoteSource(dio: dio, url: config.catalogUrl),
    cache: FileCatalogCache(
      File('${support.path}/catalog/catalog.signed.json'),
    ),
    bundled: const AssetBundledCatalogSource(),
    clock: ref.watch(clockProvider),
    logger: ref.watch(appLoggerProvider),
  );
}
