import 'package:emberwit/app/bootstrap.dart';
import 'package:emberwit/core/logging/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockLogger extends Mock implements AppLogger;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('installErrorHandlers routes framework and async errors to logger', () {
    final originalFlutterHandler = FlutterError.onError;
    final originalPlatformHandler = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = originalFlutterHandler;
      PlatformDispatcher.instance.onError = originalPlatformHandler;
    });

    final logger = _MockLogger();
    installErrorHandlers(logger);

    final error = StateError('boom');
    // Invoke the handler directly; presentError only prints in debug mode.
    FlutterError.onError!(FlutterErrorDetails(exception: error));
    verify(() => logger.error('Flutter framework error', error)).called(1);

    final handled = PlatformDispatcher.instance.onError!(
      error,
      StackTrace.empty,
    );
    expect(handled, isTrue);
    verify(
      () =>
          logger.error('Uncaught asynchronous error', error, StackTrace.empty),
    ).called(1);
  });

  test('registerBundledLicenses adds the font license', () async {
    registerBundledLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    expect(
      entries.any((e) => e.packages.contains('Noto Sans Bengali')),
      isTrue,
    );
  });
}
