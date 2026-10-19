import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Severity of a log record, ordered from least to most severe.
enum LogLevel {
  /// Fine grained diagnostics, debug builds only.
  debug,

  /// Normal lifecycle events.
  info,

  /// Something unexpected that the app recovered from.
  warning,

  /// An operation failed.
  error,
}

/// Application wide logging contract.
///
/// Privacy rule: never pass user content to a logger. That means no chat
/// messages, prompts, model output, system prompts, conversation titles or
/// file names chosen by the user. Log what happened and where, never what it
/// was about. The logger is abstract so an opt in crash reporter can be added
/// later without touching call sites.
abstract interface class AppLogger {
  /// Logs a debug diagnostic.
  void debug(String message);

  /// Logs a normal lifecycle event.
  void info(String message);

  /// Logs a recovered anomaly.
  void warning(String message);

  /// Logs a failure with an optional [error] and [stackTrace].
  void error(String message, [Object? error, StackTrace? stackTrace]);
}

/// Logger for debug and profile builds. Writes to `dart:developer`, which is
/// visible in DevTools and `flutter logs`.
final class DebugAppLogger implements AppLogger {
  /// Creates a logger that tags every record with [name] and drops records
  /// below [minLevel].
  const new({this.name = 'emberwit', this.minLevel = LogLevel.debug});

  /// Tag shown with every record.
  final String name;

  /// Records below this level are dropped.
  final LogLevel minLevel;

  @override
  void debug(String message) => _write(LogLevel.debug, message);

  @override
  void info(String message) => _write(LogLevel.info, message);

  @override
  void warning(String message) => _write(LogLevel.warning, message);

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _write(LogLevel.error, message, error, stackTrace);

  void _write(
    LogLevel level,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (level.index < minLevel.index) return;
    developer.log(
      message,
      name: name,
      level: _developerLevel(level),
      error: error,
      stackTrace: stackTrace,
    );
  }

  static int _developerLevel(LogLevel level) => switch (level) {
    LogLevel.debug => 500,
    LogLevel.info => 800,
    LogLevel.warning => 900,
    LogLevel.error => 1000,
  };
}

/// Logger for release builds. Drops everything so no diagnostic text ends up
/// in the system log of a user's phone.
final class SilentAppLogger implements AppLogger {
  /// Creates a logger that discards all records.
  const new();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warning(String message) {}

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {}
}

/// Returns the logger appropriate for the current build mode.
AppLogger createDefaultLogger() =>
    kReleaseMode ? const SilentAppLogger() : const DebugAppLogger();
