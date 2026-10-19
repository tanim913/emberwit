import 'package:emberwit/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLogger', () {
    test('DebugAppLogger accepts every level without throwing', () {
      const logger = DebugAppLogger(minLevel: LogLevel.info);
      expect(() => logger.debug('dropped below min level'), returnsNormally);
      expect(() => logger.info('info'), returnsNormally);
      expect(() => logger.warning('warning'), returnsNormally);
      expect(
        () => logger.error('error', StateError('x'), StackTrace.current),
        returnsNormally,
      );
      expect(logger.name, 'emberwit');
    });

    test('SilentAppLogger discards everything', () {
      const logger = SilentAppLogger();
      expect(() => logger.debug('a'), returnsNormally);
      expect(() => logger.info('a'), returnsNormally);
      expect(() => logger.warning('a'), returnsNormally);
      expect(() => logger.error('a', Object()), returnsNormally);
    });

    test('default logger is the debug logger outside release mode', () {
      expect(createDefaultLogger(), isA<DebugAppLogger>());
    });
  });
}
