/// The O(1) capture path (Rule 0.1). Every public capture call lands here on
/// the main isolate: stamp ids/time, estimate cost, ring-buffer add. Nothing
/// else — no serialization, no validation beyond the buffer's O(1) checks.
///
/// A periodic drain ships accumulated raw records to the engine as primitive
/// maps. The drain is the only place the buffer is read on the main isolate.
library;

import 'dart:async';

import 'package:sessionly_flutter/src/engine/capture_record.dart';
import 'package:sessionly_flutter/src/engine/ring_buffer.dart';
import 'package:sessionly_flutter/src/protocol/uuid_v7.dart';

/// Sink for drained records — a `SendPort.send` in production, a direct
/// callback in tests.
typedef RecordSink = void Function(List<Map<String, Object?>> records);

/// Owns the ring buffer and the drain timer. Capture methods are pure sync
/// enqueues; the timer batches records off the per-event hot path.
class CaptureGate {
  /// Creates a gate. [sink] receives drained batches; [uuid]/[nowMs] are
  /// injectable for deterministic tests.
  CaptureGate({
    required RingBuffer<Map<String, Object?>> buffer,
    required RecordSink sink,
    required UuidV7Generator uuid,
    int Function()? nowMs,
    Duration drainInterval = const Duration(seconds: 1),
    void Function(Object error)? onError,
  }) : _buffer = buffer,
       _sink = sink,
       _uuid = uuid,
       _nowMs = nowMs ?? _systemNowMs,
       _drainInterval = drainInterval,
       _onError = onError;

  static int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

  final RingBuffer<Map<String, Object?>> _buffer;
  final RecordSink _sink;
  final UuidV7Generator _uuid;
  final int Function() _nowMs;
  final Duration _drainInterval;
  final void Function(Object error)? _onError;

  Timer? _timer;

  int _capturedTotal = 0;
  int _droppedTotal = 0;

  /// Total capture calls admitted since construction. A debug/overlay
  /// affordance only (surfaced via `Sessionly.debugStats`); never on the wire.
  int get capturedTotal => _capturedTotal;

  /// Total records evicted by the ring buffer since construction (monotonic:
  /// accumulated across drains, so it is not reset the way the buffer's own
  /// dropped-delta is).
  int get droppedTotal => _droppedTotal;

  /// Records currently buffered and awaiting the next drain.
  int get bufferedEvents => _buffer.length;

  /// Starts the periodic drain. Idempotent.
  void start() {
    _timer ??= Timer.periodic(_drainInterval, (_) => drainNow());
  }

  /// Captures a `track`/`screen`/auto event. O(1): stamp then add.
  void captureEvent({
    required String type,
    required String name,
    required Map<String, Object?> props,
    String? screen,
  }) {
    final record = eventRecord(
      eventId: _uuid.generate(),
      tsMs: _nowMs(),
      type: type,
      name: name,
      props: props,
      screen: screen,
    );
    _capturedTotal++;
    _buffer.add(record, estimateRecordBytes(name, props, screen));
  }

  /// Captures an `identify(userId)`.
  void captureIdentify(String userId) {
    final record = identifyRecord(
      eventId: _uuid.generate(),
      tsMs: _nowMs(),
      userId: userId,
    );
    _capturedTotal++;
    _buffer.add(record, 160 + userId.length);
  }

  /// Captures a `reset()`.
  void captureReset() {
    final record = resetRecord(eventId: _uuid.generate(), tsMs: _nowMs());
    _capturedTotal++;
    _buffer.add(record, 160);
  }

  /// Drains the buffer to the sink now, prefixing any ring-buffer drop delta as
  /// a meta record so it reaches engine telemetry. Safe to call from a timer or
  /// an explicit flush; never throws (errors are counted, not propagated).
  void drainNow() {
    try {
      final dropped = _buffer.takeDroppedDelta();
      _droppedTotal += dropped;
      final records = _buffer.drain();
      if (records.isEmpty && dropped == 0) return;
      final batch = <Map<String, Object?>>[
        if (dropped > 0) droppedMetaRecord(dropped),
        ...records,
      ];
      _sink(batch);
    } on Object catch (error) {
      _onError?.call(error);
    }
  }

  /// Stops the drain timer. Does not drain — call [drainNow] first if needed.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
