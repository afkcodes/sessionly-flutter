/// Frame-timing capture (docs/05 budget: `addTimingsCallback` < 0.1 ms/frame).
///
/// The per-frame callback does the absolute minimum: for each reported frame it
/// reads one integer (total span in ms) and updates a handful of counters — no
/// allocation, no event emission, no screen lookup. All aggregation happens in
/// the windowed drain path (default every 5 s), never per frame.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:sessionly_flutter/src/capture/capture_sink.dart';
import 'package:sessionly_flutter/src/capture/current_screen.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

/// A fixed set of integer accumulators drained per window. Reused across
/// windows (reset in place) so the per-frame path never allocates.
class _FrameWindow {
  int janky = 0;
  int frozen = 0;
  int worstMs = 0;

  void reset() {
    janky = 0;
    frozen = 0;
    worstMs = 0;
  }

  bool get isEmpty => janky == 0 && frozen == 0 && worstMs == 0;
}

/// Accumulates frame timings and emits `slow_frame_burst` / `frozen_frame`.
class FrameTimingCapture {
  /// Wires to [sink]/[tracker]. Thresholds are overridable for tests; [window]
  /// is the aggregation cadence and [schedule] a timer seam.
  ///
  /// Defaults target USER-PERCEPTIBLE sustained jank, not every frame that
  /// grazes its budget. `jankyThresholdMs = 32` counts only frames that dropped
  /// at least a full 60Hz frame (more at 90/120Hz); a 16ms bar flags on-budget
  /// frames and fired constantly on mid-range Android. `burstMinFrames = 6`
  /// requires a real cluster of dropped frames before calling a stutter, so a
  /// couple of incidental slow frames stay quiet.
  FrameTimingCapture({
    required CaptureSink sink,
    required CurrentScreenTracker tracker,
    Duration window = const Duration(seconds: 5),
    int jankyThresholdMs = 32,
    int frozenThresholdMs = 700,
    int burstMinFrames = 6,
    Timer Function(Duration, void Function(Timer))? schedule,
  }) : _sink = sink,
       _tracker = tracker,
       _window = window,
       _jankyMs = jankyThresholdMs,
       _frozenMs = frozenThresholdMs,
       _burstMin = burstMinFrames,
       _schedule = schedule ?? Timer.periodic;

  final CaptureSink _sink;
  final CurrentScreenTracker _tracker;
  final Duration _window;
  final int _jankyMs;
  final int _frozenMs;
  final int _burstMin;
  final Timer Function(Duration, void Function(Timer)) _schedule;

  final _FrameWindow _acc = _FrameWindow();
  Timer? _timer;

  /// Registers the timings callback and starts the window timer.
  void install() {
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    _timer = _schedule(_window, (_) => drain());
  }

  /// Unregisters the callback and stops the timer.
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    _timer?.cancel();
    _timer = null;
  }

  /// The hot path. Per frame: one int read + a few comparisons/increments.
  /// Deliberately allocation-free (Rule 0.1 / the < 0.1 ms budget).
  void onTimings(List<FrameTiming> timings) {
    for (var i = 0; i < timings.length; i++) {
      final ms = timings[i].totalSpan.inMilliseconds;
      if (ms > _acc.worstMs) _acc.worstMs = ms;
      if (ms >= _frozenMs) {
        _acc.frozen++;
      } else if (ms >= _jankyMs) {
        _acc.janky++;
      }
    }
  }

  /// Closes the current window: emits at most one burst and one frozen event,
  /// then resets the accumulators. Runs off the per-frame path.
  void drain() {
    if (_acc.isEmpty) return;
    final screen = _tracker.current;
    if (_acc.janky >= _burstMin) {
      _sink.emit(
        type: EventType.perf,
        name: 'slow_frame_burst',
        props: {'count': _acc.janky, 'worst_ms': _acc.worstMs},
        screen: screen,
      );
    }
    if (_acc.frozen > 0) {
      _sink.emit(
        type: EventType.perf,
        name: 'frozen_frame',
        props: {'count': _acc.frozen, 'worst_ms': _acc.worstMs},
        screen: screen,
      );
    }
    _acc.reset();
  }
}
