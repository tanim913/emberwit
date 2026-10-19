/// Source of the current time, injectable so time dependent logic is testable.
abstract interface class Clock {
  /// The current local time.
  DateTime now();
}

/// [Clock] backed by the system clock.
final class SystemClock implements Clock {
  /// Creates a system clock.
  const new();

  @override
  DateTime now() => DateTime.now();
}

/// [Clock] that always returns a fixed, adjustable instant. For tests.
final class FixedClock implements Clock {
  /// Creates a clock frozen at [current].
  new(this.current);

  /// The instant returned by [now]. Mutable so tests can advance time.
  DateTime current;

  @override
  DateTime now() => current;

  /// Moves the clock forward by [duration].
  void advance(Duration duration) => current = current.add(duration);
}
