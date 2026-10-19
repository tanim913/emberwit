import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'catalog_repository.g.dart';

/// Source of the verified model catalog. Implemented by the model_catalog
/// feature and wired in `featureBindings()`.
abstract interface class CatalogRepository {
  /// The best catalog available without network access: the cached last
  /// valid download, otherwise the bundled copy. Never fails.
  Future<CatalogSnapshot> current();

  /// Downloads, verifies and caches the remote catalog. On any failure the
  /// previous catalog stays in use and the failure is returned.
  Future<Result<CatalogSnapshot>> refresh();
}

/// The catalog repository. Overridden by `featureBindings()`.
@Riverpod(keepAlive: true)
CatalogRepository catalogRepository(Ref ref) => throw StateError(
  'catalogRepositoryProvider must be overridden by featureBindings().',
);
