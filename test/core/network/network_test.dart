import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:emberwit/core/network/certificate_pins.dart';
import 'package:emberwit/core/network/secure_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pin computed with openssl:
/// openssl x509 -pubkey -noout | openssl pkey -pubin -outform der |
/// openssl dgst -sha256 -binary | base64
const _huggingFacePin = 'sha256/2MqLa/44pZTt+hMDJgp71yGHBqOjWTnulG4H5xsmyQk=';

class _ScriptedAdapter implements HttpClientAdapter {
  new(this.statuses);

  final List<int> statuses;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final status = statuses[calls.clamp(0, statuses.length - 1)];
    calls++;
    return ResponseBody.fromString('ok', status);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final der = File('test/fixtures/certs/huggingface_leaf.der')
      .readAsBytesSync();

  group('spkiPin', () {
    test('matches openssl for a real certificate', () {
      expect(spkiPin(der), _huggingFacePin);
    });

    test('returns null for garbage and truncated input', () {
      expect(spkiPin(Uint8List.fromList(utf8.encode('not a cert'))), isNull);
      expect(spkiPin(Uint8List.sublistView(der, 0, 40)), isNull);
      expect(spkiPin(Uint8List(0)), isNull);
    });
  });

  group('CertificatePinner', () {
    test('allows only listed keys for pinned hosts', () {
      const pinner = CertificatePinner({
        'huggingface.co': [_huggingFacePin],
        'catalog.example.org': ['sha256/AAAA'],
      });
      expect(pinner.isPinned('huggingface.co'), isTrue);
      expect(pinner.allows('huggingface.co', der), isTrue);
      expect(pinner.allows('catalog.example.org', der), isFalse);
    });

    test('leaves unpinned hosts to the system trust store', () {
      const pinner = CertificatePinner({'catalog.example.org': []});
      expect(pinner.isPinned('catalog.example.org'), isFalse);
      expect(pinner.allows('other.org', der), isTrue);
    });
  });

  group('createSecureDio', () {
    test('refuses plain HTTP', () async {
      final dio = createSecureDio();
      await expectLater(
        dio.get<void>('http://example.org/catalog.json'),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.badCertificate,
          ),
        ),
      );
    });

    test('retries transient errors, then succeeds', () async {
      final dio = createSecureDio();
      final adapter = _ScriptedAdapter([503, 502, 200]);
      dio
        ..httpClientAdapter = adapter
        ..interceptors.removeWhere((i) => i is RetryInterceptor)
        ..interceptors.add(
          RetryInterceptor(dio, baseDelay: const Duration(milliseconds: 1)),
        );
      final response = await dio.get<String>('https://example.org/c.json');
      expect(response.statusCode, 200);
      expect(adapter.calls, 3);
    });

    test('gives up after the retry limit and never retries 4xx', () async {
      final dio = createSecureDio();
      final failing = _ScriptedAdapter([500]);
      dio
        ..httpClientAdapter = failing
        ..interceptors.removeWhere((i) => i is RetryInterceptor)
        ..interceptors.add(
          RetryInterceptor(
            dio,
            retries: 2,
            baseDelay: const Duration(milliseconds: 1),
          ),
        );
      await expectLater(
        dio.get<String>('https://example.org/c.json'),
        throwsA(isA<DioException>()),
      );
      expect(failing.calls, 3);

      final notFound = _ScriptedAdapter([404]);
      dio.httpClientAdapter = notFound;
      await expectLater(
        dio.get<String>('https://example.org/c.json'),
        throwsA(isA<DioException>()),
      );
      expect(notFound.calls, 1);
    });

    test('classifies transient errors', () {
      DioException error(DioExceptionType type, [int? status]) => DioException(
        requestOptions: RequestOptions(),
        type: type,
        response: status == null
            ? null
            : Response<void>(
                requestOptions: RequestOptions(),
                statusCode: status,
              ),
      );
      expect(
        RetryInterceptor.isTransient(error(DioExceptionType.connectionError)),
        isTrue,
      );
      expect(
        RetryInterceptor.isTransient(error(DioExceptionType.receiveTimeout)),
        isTrue,
      );
      expect(
        RetryInterceptor.isTransient(error(DioExceptionType.badResponse, 429)),
        isTrue,
      );
      expect(
        RetryInterceptor.isTransient(error(DioExceptionType.badResponse, 403)),
        isFalse,
      );
      expect(
        RetryInterceptor.isTransient(error(DioExceptionType.badCertificate)),
        isFalse,
      );
      expect(
        RetryInterceptor.isTransient(error(DioExceptionType.cancel)),
        isFalse,
      );
    });
  });
}
