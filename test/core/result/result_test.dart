import 'package:emberwit/core/errors/app_failure.dart';
import 'package:emberwit/core/result/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const failure = ConfigurationFailure('bad');

  group('Result', () {
    test('ok exposes value and no failure', () {
      const result = Result<int>.ok(1);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 1);
      expect(result.failureOrNull, isNull);
    });

    test('err exposes failure and no value', () {
      const result = Result<int>.err(failure);
      expect(result.isOk, isFalse);
      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, failure);
    });

    test('fold picks the matching branch', () {
      expect(const Ok(2).fold(ok: (v) => 'v$v', err: (f) => f.code), 'v2');
      expect(
        const Err<int>(failure).fold(ok: (v) => 'v$v', err: (f) => f.code),
        'configuration',
      );
    });

    test('map transforms values and keeps failures', () {
      expect(const Ok(2).map((v) => v * 3), const Ok(6));
      expect(
        const Err<int>(failure).map((v) => v * 3),
        const Err<int>(failure),
      );
    });

    test('flatMap chains fallible steps', () {
      Result<int> half(int v) =>
          v.isEven ? Ok(v ~/ 2) : const Err(ConfigurationFailure('odd'));

      expect(const Ok(8).flatMap(half).flatMap(half), const Ok(2));
      expect(
        const Ok(6).flatMap(half).flatMap(half),
        const Err<int>(ConfigurationFailure('odd')),
      );
      expect(const Err<int>(failure).flatMap(half), const Err<int>(failure));
    });

    test('mapFailure transforms failures and keeps values', () {
      const other = ConfigurationFailure('other');
      expect(const Ok(1).mapFailure((_) => other), const Ok(1));
      expect(
        const Err<int>(failure).mapFailure((_) => other),
        const Err<int>(other),
      );
    });

    test('getOrElse returns value or fallback', () {
      expect(const Ok(1).getOrElse((_) => 0), 1);
      expect(const Err<int>(failure).getOrElse((_) => 0), 0);
    });

    test('guard wraps values and converts thrown errors', () async {
      expect(await Result.guard(() => 5), const Ok(5));
      expect(await Result.guard(() async => 'a'), const Ok('a'));

      final unexpected = await Result.guard<int>(
        () => throw const FormatException('x'),
      );
      expect(unexpected.failureOrNull, isA<UnexpectedFailure>());
      expect(unexpected.failureOrNull!.cause, isA<FormatException>());
      expect(unexpected.failureOrNull!.stackTrace, isNotNull);

      final mapped = await Result.guard<int>(
        () => throw StateError('x'),
        onError: (e, s) => const ConfigurationFailure('mapped'),
      );
      expect(mapped, const Err<int>(ConfigurationFailure('mapped')));
    });

    test('equality, hashCode and toString', () {
      expect(const Ok(1), const Ok(1));
      expect(const Ok(1).hashCode, const Ok(1).hashCode);
      expect(const Ok(1), isNot(const Ok(2)));
      expect(const Err<int>(failure).hashCode, failure.hashCode);
      expect(const Ok(1).toString(), 'Ok(1)');
      expect(const Err<int>(failure).toString(), contains('configuration'));
    });

    test('supports exhaustive pattern matching', () {
      String describe(Result<int> r) => switch (r) {
        Ok(:final value) => 'ok $value',
        Err(:final failure) => 'err ${failure.code}',
      };
      expect(describe(const Ok(1)), 'ok 1');
      expect(describe(const Err(failure)), 'err configuration');
    });
  });
}
