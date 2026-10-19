import 'dart:async';

import 'package:emberwit/core/errors/app_failure.dart';
import 'package:flutter/foundation.dart';

/// The outcome of an operation that can fail in an expected way.
///
/// Domain and data layers return [Result] instead of throwing, so failures are
/// part of the type signature and cannot be forgotten by callers.
///
/// ```dart
/// final result = await repository.load();
/// final text = switch (result) {
///   Ok(:final value) => value.name,
///   Err(:final failure) => failure.code,
/// };
/// ```
@immutable
sealed class Result<T> {
  const new();

  /// Creates a successful result holding [value].
  const factory ok(T value) = Ok<T>;

  /// Creates a failed result holding [failure].
  const factory err(AppFailure failure) = Err<T>;

  /// Runs [body] and converts any thrown error into an [Err].
  ///
  /// Use only at the edge of the data layer where third party code throws.
  /// [onError] maps the error to a specific [AppFailure]; without it the
  /// error becomes an [UnexpectedFailure].
  static Future<Result<T>> guard<T>(
    FutureOr<T> Function() body, {
    AppFailure Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      return Ok<T>(await body());
    } on Object catch (error, stackTrace) {
      return Err<T>(
        onError?.call(error, stackTrace) ??
            UnexpectedFailure(cause: error, stackTrace: stackTrace),
      );
    }
  }

  /// Whether this is an [Ok].
  bool get isOk => this is Ok<T>;

  /// Whether this is an [Err].
  bool get isErr => this is Err<T>;

  /// The success value, or `null` when this is an [Err].
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  /// The failure, or `null` when this is an [Ok].
  AppFailure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final failure) => failure,
  };

  /// Collapses both sides into a single value of type [R].
  R fold<R>({
    required R Function(T value) ok,
    required R Function(AppFailure failure) err,
  }) => switch (this) {
    Ok<T>(:final value) => ok(value),
    Err<T>(:final failure) => err(failure),
  };

  /// Transforms the success value, keeping failures untouched.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T>(:final value) => Ok<R>(transform(value)),
    Err<T>(:final failure) => Err<R>(failure),
  };

  /// Chains an operation that itself can fail.
  Result<R> flatMap<R>(Result<R> Function(T value) transform) => switch (this) {
    Ok<T>(:final value) => transform(value),
    Err<T>(:final failure) => Err<R>(failure),
  };

  /// Transforms the failure, keeping success values untouched.
  Result<T> mapFailure(AppFailure Function(AppFailure failure) transform) =>
      switch (this) {
        Ok<T>() => this,
        Err<T>(:final failure) => Err<T>(transform(failure)),
      };

  /// The success value, or the value produced by [orElse] for a failure.
  T getOrElse(T Function(AppFailure failure) orElse) => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>(:final failure) => orElse(failure),
  };
}

/// A successful [Result].
final class Ok<T> extends Result<T> {
  /// Wraps a success [value].
  const new(this.value);

  /// The success value.
  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Ok<T> && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Ok($value)';
}

/// A failed [Result].
final class Err<T> extends Result<T> {
  /// Wraps a [failure].
  const new(this.failure);

  /// The failure describing what went wrong.
  final AppFailure failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Err<T> && other.failure == failure);

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'Err($failure)';
}
