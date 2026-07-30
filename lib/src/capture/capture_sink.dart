/// The one choke point every auto-capture surface emits through. Surfaces never
/// touch the [CaptureGate] directly — they call [CaptureSink.emit], which keeps
/// them decoupled from the engine and trivially fakeable in widget tests.
library;

import 'package:sessionly_flutter/src/engine/capture_gate.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

/// Emits a governed auto/lifecycle/error/perf/frustration event. The
/// implementation guarantees Rule 0.3 (never throws into the host).
// ignore: one_member_abstracts
abstract interface class CaptureSink {
  /// Records one event. [type]/[name] must be a governed vocabulary pair; the
  /// call is O(1) and non-throwing. [tsMs] overrides the capture time for a
  /// surface that stamped the true event moment earlier than this call (a tap
  /// stamps on pointer-up, then resolves its target post-frame); omit for now.
  void emit({
    required EventType type,
    required String name,
    Map<String, Object?> props,
    String? screen,
    int? tsMs,
  });
}

/// [CaptureSink] backed by the real [CaptureGate]. Every emit is wrapped so a
/// surface can never propagate an exception into a Flutter callback.
class GateCaptureSink implements CaptureSink {
  /// Wraps [gate]; swallowed failures are counted via [onError].
  GateCaptureSink({
    required CaptureGate gate,
    void Function(Object error)? onError,
  }) : _gate = gate,
       _onError = onError;

  final CaptureGate _gate;
  final void Function(Object error)? _onError;

  @override
  void emit({
    required EventType type,
    required String name,
    Map<String, Object?> props = const {},
    String? screen,
    int? tsMs,
  }) {
    try {
      _gate.captureEvent(
        type: type.name,
        name: name,
        props: props,
        screen: screen,
        atMs: tsMs,
      );
    } on Object catch (error) {
      _onError?.call(error);
    }
  }
}
