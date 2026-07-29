/// SDK self-telemetry (docs/05 invariant 1). Every drop point in the engine
/// increments a counter here; at most once per hour, and only when a counter is
/// nonzero, they are emitted as a single `custom` / `sdk_health` event and reset.
library;

/// Mutable counter set describing where the engine shed load. The names double
/// as the `props` of the emitted `sdk_health` event.
class Telemetry {
  /// Creates a telemetry counter set.
  Telemetry({int emitIntervalMs = 3600 * 1000})
    : _emitIntervalMs = emitIntervalMs;

  final int _emitIntervalMs;
  int _lastEmitMs = 0;

  /// Events dropped by the in-memory ring buffer (Rule 0.4).
  int droppedBuffer = 0;

  /// Events evicted from the on-disk queue (LRU, Rule 0.4/5).
  int droppedDisk = 0;

  /// Events dropped for invalid `props` (docs/05 invariant 1).
  int invalidProps = 0;

  /// Swallowed internal errors (Rule 0.3).
  int internalErrors = 0;

  /// Failed/aborted upload attempts.
  int uploadFailures = 0;

  /// Upload attempts terminated by a 401 auth halt (Rule 0.3). Distinct from
  /// [uploadFailures] so a bad/rotated write key is unmistakable in the health
  /// event rather than hiding among transient failures.
  int uploadHalts = 0;

  /// `true` when any counter is nonzero.
  bool get hasPending =>
      droppedBuffer != 0 ||
      droppedDisk != 0 ||
      invalidProps != 0 ||
      internalErrors != 0 ||
      uploadFailures != 0 ||
      uploadHalts != 0;

  /// If a full interval has elapsed and something is pending, returns the
  /// `props` for an `sdk_health` event and resets the counters. Otherwise
  /// returns `null`. [nowMs] is injected for deterministic tests.
  Map<String, Object?>? maybeDrain(int nowMs) {
    if (!hasPending) return null;
    if (_lastEmitMs != 0 && nowMs - _lastEmitMs < _emitIntervalMs) return null;
    final props = <String, Object?>{
      'dropped_buffer': droppedBuffer,
      'dropped_disk': droppedDisk,
      'invalid_props': invalidProps,
      'internal_errors': internalErrors,
      'upload_failures': uploadFailures,
      'upload_halts': uploadHalts,
    };
    droppedBuffer = 0;
    droppedDisk = 0;
    invalidProps = 0;
    internalErrors = 0;
    uploadFailures = 0;
    uploadHalts = 0;
    _lastEmitMs = nowMs;
    return props;
  }
}
