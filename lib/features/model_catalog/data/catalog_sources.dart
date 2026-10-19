import 'dart:io';

import 'package:dio/dio.dart';
import 'package:emberwit/features/model_catalog/data/catalog_trust.dart';
import 'package:flutter/services.dart';

/// Downloads the signed catalog.
abstract interface class CatalogRemoteSource {
  /// The raw envelope bytes. Throws [DioException] on network errors.
  Future<Uint8List> fetch();
}

/// [CatalogRemoteSource] over the app's secure HTTP client.
final class DioCatalogRemoteSource implements CatalogRemoteSource {
  /// Creates the source for [url].
  const new({required this.dio, required this.url});

  /// Secure client (HTTPS only, pinned, retrying).
  final Dio dio;

  /// Catalog URL of the current flavor.
  final Uri url;

  @override
  Future<Uint8List> fetch() async {
    final response = await dio.getUri<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'accept': 'application/json'},
      ),
    );
    final bytes = response.data ?? const [];
    if (bytes.length > maxCatalogBytes) {
      throw DioException(
        requestOptions: response.requestOptions,
        message: 'catalog larger than $maxCatalogBytes bytes',
      );
    }
    return Uint8List.fromList(bytes);
  }
}

/// Stores the last verified envelope.
abstract interface class CatalogCache {
  /// The cached envelope, or `null`.
  Future<Uint8List?> read();

  /// Replaces the cached envelope.
  Future<void> write(Uint8List envelope);
}

/// [CatalogCache] in a file, written atomically.
final class FileCatalogCache implements CatalogCache {
  /// Creates a cache stored in [file].
  const new(this.file);

  /// The cache file.
  final File file;

  @override
  Future<Uint8List?> read() async =>
      file.existsSync() ? await file.readAsBytes() : null;

  @override
  Future<void> write(Uint8List envelope) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(envelope, flush: true);
    await temporary.rename(file.path);
  }
}

/// Loads the catalog shipped inside the app.
abstract interface class BundledCatalogSource {
  /// The bundled envelope bytes.
  Future<Uint8List> load();
}

/// [BundledCatalogSource] reading a Flutter asset.
final class AssetBundledCatalogSource implements BundledCatalogSource {
  /// Creates the source.
  const new([this.asset = bundledCatalogAsset]);

  /// Asset key.
  final String asset;

  @override
  Future<Uint8List> load() async {
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
