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
    Duration screenViewDedupWindow = const Duration(milliseconds: 700),
    void Function(Object error)? onError,
  }) : _buffer = buffer,
       _sink = sink,
       _uuid = uuid,
       _nowMs = nowMs ?? _systemNowMs,
       _drainInterval = drainInterval,
       _screenViewDedupMs = screenViewDedupWindow.inMilliseconds,
       _onError = onError;

  static int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

  /// Governed name whose consecutive same-screen repeats are coalesced. A
  /// common integration (a shell/tab route that fires the navigator observer AND
  /// a manual `Sessionly.screen()`) emits two `screen_view`s ~1 frame apart for
  /// one navigation; counting both doubles every screen view. Only this name is
  /// deduped.
  static const _screenViewName = 'screen_view';

  final RingBuffer<Map<String, Object?>> _buffer;
  final RecordSink _sink;
  final UuidV7Generator _uuid;
  final int Function() _nowMs;
  final Duration _drainInterval;
  final int _screenViewDedupMs;
  final void Function(Object error)? _onError;

  Timer? _timer;

  int _capturedTotal = 0;
  int _droppedTotal = 0;
  int _dedupedTotal = 0;

  /// The last admitted `screen_view`, for same-screen coalescing within
  /// [_screenViewDedupMs]. The buffered record is held by reference so a later,
  /// richer duplicate can ENRICH it in place rather than lose its props — the
  /// observer's nav_type/previous_screen and the bare manual `Sessionly.screen()`
  /// fire in either order, and we keep the union's best. Cleared on drain (the
  /// record leaves the buffer). `null` screen never dedups.
  String? _lastScreenViewScreen;
  int _lastScreenViewAtMs = 0;
  Map<String, Object?>? _lastScreenViewRecord;
  int _lastScreenViewPropsLen = 0;

  /// Total capture calls admitted since construction. A debug/overlay
  /// affordance only (surfaced via `Sessionly.debugStats`); never on the wire.
  int get capturedTotal => _capturedTotal;

  /// Total records evicted by the ring buffer since construction (monotonic:
  /// accumulated across drains, so it is not reset the way the buffer's own
  /// dropped-delta is).
  int get droppedTotal => _droppedTotal;

  /// Consecutive duplicate `screen_view`s suppressed since construction (debug/overlay
  /// affordance only; never on the wire).
  int get dedupedTotal => _dedupedTotal;

  /// Records currently buffered and awaiting the next drain.
  int get bufferedEvents => _buffer.length;

  /// Starts the periodic drain. Idempotent.
  void start() {
    _timer ??= Timer.periodic(_drainInterval, (_) => drainNow());
  }

  /// Captures a `track`/`screen`/auto event. O(1): stamp then add.
  ///
  /// Consecutive `screen_view`s for the SAME screen within the dedup window
  /// collapse to one: a shell/tab route commonly fires both the navigator
  /// observer and a manual `Sessionly.screen()` for one navigation, so counting
  /// both doubles the metric. The survivor keeps the EARLIEST timestamp and the
  /// RICHER props (whichever of the two carried more), so no nav_type /
  /// previous_screen edge is lost regardless of which fired first.
  void captureEvent({
    required String type,
    required String name,
    required Map<String, Object?> props,
    String? screen,
  }) {
    final tsMs = _nowMs();
    if (name == _screenViewName && screen != null) {
      if (screen == _lastScreenViewScreen &&
          tsMs - _lastScreenViewAtMs <= _screenViewDedupMs) {
        _dedupedTotal++;
        // Enrich the already-buffered view in place when this duplicate carries
        // more props (adds a few uncounted bytes — negligible against the cap).
        final buffered = _lastScreenViewRecord;
        if (buffered != null && props.length > _lastScreenViewPropsLen) {
          buffered[RecordKey.props] = props;
          _lastScreenViewPropsLen = props.length;
        }
        return;
      }
    }
    final record = eventRecord(
      eventId: _uuid.generate(),
      tsMs: tsMs,
      type: type,
      name: name,
      props: props,
      screen: screen,
    );
    _capturedTotal++;
    _buffer.add(record, estimateRecordBytes(name, props, screen));
    if (name == _screenViewName && screen != null) {
      _lastScreenViewScreen = screen;
      _lastScreenViewAtMs = tsMs;
      _lastScreenViewRecord = record;
      _lastScreenViewPropsLen = props.length;
    }
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
      // The buffered screen_view just left the buffer — drop the enrich handle
      // so a later duplicate can't mutate an already-shipped record (it still
      // dedups by screen+time, keeping the count correct).
      _lastScreenViewRecord = null;
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
