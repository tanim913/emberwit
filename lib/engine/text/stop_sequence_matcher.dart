/// Result of feeding text to a [StopSequenceMatcher].
typedef StopMatch = ({String emit, bool stopped});

/// Finds stop sequences in streamed text without leaking them.
///
/// Text that could be the beginning of a stop sequence is held back until it
/// is either confirmed (generation stops and the sequence is dropped) or
/// ruled out (the text is emitted).
final class StopSequenceMatcher {
  /// Creates a matcher for [stopSequences]. Empty strings are ignored.
  new(Iterable<String> stopSequences)
    : _stops = stopSequences.where((s) => s.isNotEmpty).toList();

  final List<String> _stops;
  String _pending = '';
  bool _stopped = false;

  /// Whether a stop sequence was found.
  bool get stopped => _stopped;

  /// Adds [text]. Returns the text that is safe to show and whether a stop
  /// sequence was reached. After a stop, further input is ignored.
  StopMatch add(String text) {
    if (_stopped) return (emit: '', stopped: true);
    if (_stops.isEmpty) return (emit: text, stopped: false);

    final buffer = _pending + text;
    var earliest = -1;
    for (final stop in _stops) {
      final index = buffer.indexOf(stop);
      if (index >= 0 && (earliest < 0 || index < earliest)) earliest = index;
    }
    if (earliest >= 0) {
      _stopped = true;
      _pending = '';
      return (emit: buffer.substring(0, earliest), stopped: true);
    }

    final hold = _longestPrefixSuffix(buffer);
    _pending = buffer.substring(buffer.length - hold);
    return (emit: buffer.substring(0, buffer.length - hold), stopped: false);
  }

  /// Returns held back text at the end of generation.
  String flush() {
    final rest = _stopped ? '' : _pending;
    _pending = '';
    return rest;
  }

  /// Length of the longest suffix of [buffer] that is a proper prefix of a
  /// stop sequence.
  int _longestPrefixSuffix(String buffer) {
    var best = 0;
    for (final stop in _stops) {
      final max = stop.length - 1 < buffer.length
          ? stop.length - 1
          : buffer.length;
      for (var length = max; length > best; length--) {
        if (buffer.endsWith(stop.substring(0, length))) {
          best = length;
          break;
        }
      }
    }
    return best;
  }
}
