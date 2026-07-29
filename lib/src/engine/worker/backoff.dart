/// Exponential backoff with full jitter (Rule 0.6): base 2 s, cap 5 min. Full
/// jitter (delay uniform in `0..ceiling`) spreads retries so a recovering
/// backend is not hit by a synchronized thundering herd (Rule 0.7).
library;

import 'dart:math';

/// Stateful backoff calculator. The `random` source is injectable so tests can
/// assert the jitter bounds deterministically.
class Backoff {
  /// Creates a backoff with [baseMs] base and [capMs] ceiling.
  Backoff({this.baseMs = 2000, this.capMs = 300000, Random? random})
    : _random = random ?? Random();

  /// Base delay in ms.
  final int baseMs;

  /// Maximum ceiling in ms.
  final int capMs;

  final Random _random;
  int _attempt = 0;
  int _lastCeilingMs = 0;

  /// Number of consecutive failures.
  int get attempt => _attempt;

  /// The exponential ceiling used by the most recent [nextDelayMs] — the upper
  /// bound the returned jittered delay is guaranteed to respect.
  int get lastCeilingMs => _lastCeilingMs;

  /// Advances the attempt counter and returns a jittered delay in
  /// `[0, min(capMs, baseMs * 2^(attempt-1))]`.
  int nextDelayMs() {
    _attempt++;
    final shift = _attempt - 1 > 30 ? 30 : _attempt - 1;
    final ceiling = min(capMs, baseMs * (1 << shift));
    _lastCeilingMs = ceiling;
    return _random.nextInt(ceiling + 1);
  }

  /// Resets the counter after a success.
  void reset() {
    _attempt = 0;
    _lastCeilingMs = 0;
  }
}
