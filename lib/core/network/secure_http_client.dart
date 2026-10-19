import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:emberwit/core/network/certificate_pins.dart';

/// Creates the app's HTTP client for catalog requests.
///
/// - HTTPS only: plain HTTP requests are refused before any connection.
///   Android additionally forbids cleartext in its network security config.
/// - TLS uses the platform stack; Dart's BoringSSL never negotiates below
///   TLS 1.2.
/// - Certificates are checked against the system trust store and, for pinned
///   hosts, against [pinner].
/// - Transient failures are retried with backoff by [RetryInterceptor].
/// - No cookies, no user identifiers, a fixed user agent.
Dio createSecureDio({
  CertificatePinner pinner = const CertificatePinner({}),
  Duration connectTimeout = const Duration(seconds: 15),
  Duration receiveTimeout = const Duration(seconds: 30),
  int retries = 3,
}) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      headers: {'user-agent': 'Emberwit'},
      followRedirects: true,
      maxRedirects: 3,
    ),
  );
  return dio
    ..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient()..connectionTimeout = connectTimeout,
      validateCertificate: (certificate, host, port) {
        if (certificate == null) return !pinner.isPinned(host);
        return pinner.allows(host, certificate.der);
      },
    )
    ..interceptors.addAll([
      const HttpsOnlyInterceptor(),
      RetryInterceptor(dio, retries: retries),
    ]);
}

/// Rejects any request that is not HTTPS.
final class HttpsOnlyInterceptor extends Interceptor {
  /// Creates the interceptor.
  const new();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.uri.scheme != 'https') {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badCertificate,
          message: 'Only HTTPS requests are allowed',
        ),
      );
      return;
    }
    handler.next(options);
  }
}

/// Retries requests that failed for transient reasons (timeouts, connection
/// errors, HTTP 408, 429 and 5xx) with exponential backoff. Certificate and
/// other client errors are never retried.
final class RetryInterceptor extends Interceptor {
  /// Creates the interceptor for [dio].
  new(
    this.dio, {
    this.retries = 3,
    this.baseDelay = const Duration(milliseconds: 500),
  });

  /// Client used to re-send requests.
  final Dio dio;

  /// Maximum retries per request.
  final int retries;

  /// Delay before the first retry; doubles each time.
  final Duration baseDelay;

  static const _attemptKey = 'emberwit.retry.attempt';

  /// Whether [error] is worth retrying.
  static bool isTransient(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode ?? 0;
        return status == 408 || status == 429 || status >= 500;
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.unknown:
        return false;
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final attempt = (err.requestOptions.extra[_attemptKey] as int?) ?? 0;
    if (attempt >= retries || !isTransient(err)) {
      handler.next(err);
      return;
    }
    await Future<void>.delayed(baseDelay * (1 << attempt));
    final options = err.requestOptions..extra[_attemptKey] = attempt + 1;
    try {
      handler.resolve(await dio.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}
