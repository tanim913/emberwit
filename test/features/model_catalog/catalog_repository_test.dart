import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:emberwit/core/catalog/model_catalog.dart';
import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/features/model_catalog/data/catalog_repository_impl.dart';
import 'package:emberwit/features/model_catalog/data/catalog_sources.dart';
import 'package:emberwit/features/model_catalog/data/catalog_trust.dart';
import 'package:emberwit/features/model_catalog/data/signed_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/catalog_fixtures.dart';

class _Remote implements CatalogRemoteSource {
  Uint8List? bytes;
  DioException? error;
  int calls = 0;

  @override
  Future<Uint8List> fetch() async {
    calls++;
    if (error != null) throw error!;
    return bytes!;
  }
}

class _MemoryCache implements CatalogCache {
  Uint8List? stored;

  @override
  Future<Uint8List?> read() async => stored;

  @override
  Future<void> write(Uint8List envelope) async => stored = envelope;
}

class _Bundled implements BundledCatalogSource {
  new(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> load() async => bytes;
}

void main() {
  late TestSigner signer;
  late _Remote remote;
  late _MemoryCache cache;

  setUpAll(() async => signer = await TestSigner.create());
  setUp(() {
    remote = _Remote();
    cache = _MemoryCache();
  });

  Future<CatalogRepositoryImpl> repository({int bundledVersion = 1}) async =>
      CatalogRepositoryImpl(
        verifier: SignedCatalogVerifier(signer.trustedKeys),
        remote: remote,
        cache: cache,
        bundled: _Bundled(
          await signer.sign(manifestJson(version: bundledVersion)),
        ),
      );

  test('uses the bundled catalog on first launch, offline', () async {
    final snapshot = await (await repository()).current();
    expect(snapshot.source, CatalogSource.bundled);
    expect(snapshot.catalog.catalogVersion, 1);
    expect(remote.calls, 0);
  });

  test('prefers a cached catalog that is at least as new', () async {
    cache.stored = await signer.sign(manifestJson(version: 3));
    final snapshot = await (await repository()).current();
    expect(snapshot.source, CatalogSource.cache);
    expect(snapshot.catalog.catalogVersion, 3);
  });

  test('prefers a newer bundled catalog after an app update', () async {
    cache.stored = await signer.sign(manifestJson());
    final snapshot = await (await repository(bundledVersion: 5)).current();
    expect(snapshot.source, CatalogSource.bundled);
  });

  test('ignores a cached catalog that fails verification', () async {
    cache.stored = await (await TestSigner.create()).sign(
      manifestJson(version: 9),
    );
    final snapshot = await (await repository()).current();
    expect(snapshot.source, CatalogSource.bundled);
  });

  test(
    'an invalid bundled catalog yields an empty list, not a crash',
    () async {
      final repo = CatalogRepositoryImpl(
        verifier: SignedCatalogVerifier(signer.trustedKeys),
        remote: remote,
        cache: cache,
        bundled: _Bundled(Uint8List.fromList([1, 2, 3])),
      );
      expect((await repo.current()).catalog.models, isEmpty);
    },
  );

  test('refresh verifies, caches and switches to the remote catalog', () async {
    final repo = await repository();
    remote.bytes = await signer.sign(manifestJson(version: 4));
    final result = await repo.refresh();
    expect(result.valueOrNull!.source, CatalogSource.remote);
    expect(result.valueOrNull!.catalog.catalogVersion, 4);
    expect(cache.stored, remote.bytes);
    expect((await repo.current()).catalog.catalogVersion, 4);
  });

  test('refresh keeps the current catalog on network errors', () async {
    final repo = await repository();
    remote.error = DioException(
      requestOptions: RequestOptions(),
      type: DioExceptionType.connectionError,
    );
    expect(
      (await repo.refresh()).failureOrNull,
      const CatalogFailure(CatalogFailureReason.network),
    );
    expect((await repo.current()).source, CatalogSource.bundled);
  });

  test('refresh rejects unsigned and older catalogs', () async {
    final repo = await repository(bundledVersion: 5);
    remote.bytes = await (await TestSigner.create()).sign(
      manifestJson(version: 6),
    );
    expect(
      (await repo.refresh()).failureOrNull,
      const CatalogFailure(CatalogFailureReason.invalidSignature),
    );
    remote.bytes = await signer.sign(manifestJson(version: 4));
    expect(
      (await repo.refresh()).failureOrNull,
      const CatalogFailure(CatalogFailureReason.rollback),
    );
    expect(cache.stored, isNull);
  });

  group('FileCatalogCache', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('catalog'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes atomically and reads back', () async {
      final cache = FileCatalogCache(File('${dir.path}/c/catalog.json'));
      expect(await cache.read(), isNull);
      await cache.write(Uint8List.fromList([1, 2, 3]));
      expect(await cache.read(), [1, 2, 3]);
      expect(File('${dir.path}/c/catalog.json.tmp').existsSync(), isFalse);
    });
  });

  remoteSourceTests();

  test('the asset source loads the bundled catalog', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await const AssetBundledCatalogSource().load();
    expect(bytes.length, greaterThan(1000));
  });
}

class _BytesAdapter implements HttpClientAdapter {
  new(this.length);

  final int length;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromBytes(List.filled(length, 65), 200);
  }

  @override
  void close({bool force = false}) {}
}

// The remote source fetches bytes and enforces the size limit.
void remoteSourceTests() {
  test('remote source returns the response bytes', () async {
    final adapter = _BytesAdapter(10);
    final dio = Dio()..httpClientAdapter = adapter;
    final bytes = await DioCatalogRemoteSource(
      dio: dio,
      url: Uri.parse('https://catalog.example.org/c.json'),
    ).fetch();
    expect(bytes, hasLength(10));
    expect(adapter.last!.uri.host, 'catalog.example.org');
  });

  test('remote source rejects oversized catalogs', () async {
    final dio = Dio()..httpClientAdapter = _BytesAdapter(maxCatalogBytes + 1);
    await expectLater(
      DioCatalogRemoteSource(
        dio: dio,
        url: Uri.parse('https://catalog.example.org/c.json'),
      ).fetch(),
      throwsA(isA<DioException>()),
    );
  });
}
