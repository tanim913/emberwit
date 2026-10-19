import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:emberwit/core/catalog/catalog_repository.dart';
import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/logging/app_logger.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:emberwit/core/utils/clock.dart';
import 'package:emberwit/features/model_catalog/data/catalog_sources.dart';
import 'package:emberwit/features/model_catalog/data/signed_catalog.dart';

/// [CatalogRepository] that trusts only signed catalogs.
///
/// Offline, it uses the newest valid catalog among the cache and the copy
/// bundled with the app. Online, [refresh] downloads the remote catalog,
/// verifies it, refuses older versions (rollback protection) and caches it.
final class CatalogRepositoryImpl implements CatalogRepository {
  /// Creates the repository.
  new({
    required this._verifier,
    required this._remote,
    required this._cache,
    required this._bundled,
    this._clock = const SystemClock(),
    this._logger = const SilentAppLogger(),
  });

  final SignedCatalogVerifier _verifier;
  final CatalogRemoteSource _remote;
  final CatalogCache _cache;
  final BundledCatalogSource _bundled;
  final Clock _clock;
  final AppLogger _logger;

  CatalogSnapshot? _current;

  @override
  Future<CatalogSnapshot> current() async {
    final existing = _current;
    if (existing != null) return existing;

    ModelCatalog? cached;
    final cachedBytes = await _cache.read();
    if (cachedBytes != null) {
      cached = (await _verifier.verify(cachedBytes)).valueOrNull;
      if (cached == null) _logger.warning('Cached catalog rejected');
    }
    final bundled = (await _verifier.verify(await _bundled.load()))
        .getOrElse((failure) {
          // A bundled catalog that fails verification is a build error.
          _logger.error('Bundled catalog rejected: ${failure.code}');
          return ModelCatalog(
            schemaVersion: supportedCatalogSchemaVersion,
            catalogVersion: 0,
            generatedAt: DateTime.utc(2026),
            models: const [],
          );
        });

    // An app update may ship a newer catalog than the one cached.
    final useCache =
        cached != null && cached.catalogVersion >= bundled.catalogVersion;
    return _current = CatalogSnapshot(
      catalog: useCache ? cached : bundled,
      source: useCache ? CatalogSource.cache : CatalogSource.bundled,
      loadedAt: _clock.now(),
    );
  }

  @override
  Future<Result<CatalogSnapshot>> refresh() async {
    final previous = await current();
    final Uint8List bytes;
    try {
      bytes = await _remote.fetch();
    } on DioException catch (error, stackTrace) {
      _logger.warning('Catalog download failed: ${error.type.name}');
      return Err(
        CatalogFailure(
          CatalogFailureReason.network,
          cause: error.type.name,
          stackTrace: stackTrace,
        ),
      );
    }
    final verified = await _verifier.verify(bytes);
    switch (verified) {
      case Err(:final failure):
        _logger.warning('Remote catalog rejected: ${failure.code}');
        return Err(failure);
      case Ok(:final value):
        if (value.catalogVersion < previous.catalog.catalogVersion) {
          return const Err(CatalogFailure(CatalogFailureReason.rollback));
        }
        await _cache.write(bytes);
        return Ok(
          _current = CatalogSnapshot(
            catalog: value,
            source: CatalogSource.remote,
            loadedAt: _clock.now(),
          ),
        );
    }
  }
}
