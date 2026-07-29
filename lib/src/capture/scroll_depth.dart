/// Per-screen scroll-depth capture (docs/05). A `SessionlyRoot`-installed
/// `NotificationListener<ScrollNotification>` feeds each scroll's normalized
/// fraction here; `record` is O(1) (a `max` update, no allocation). The
/// highest bucket reached is emitted once when the screen is left — reusing the
/// web SDK's `auto/scroll_depth` + `depth_pct ∈ {25,50,75,100}` contract.
library;

import 'package:sessionly_flutter/src/capture/capture_sink.dart';
import 'package:sessionly_flutter/src/capture/current_screen.dart';
import 'package:sessionly_flutter/src/protocol/capture_props.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

/// Accumulates the deepest scroll fraction for the current screen and emits it
/// (bucketed) on screen exit. Bind to a [CurrentScreenTracker] via [onScreen].
class ScrollDepthTracker {
  /// Wires the tracker to [sink]/[tracker].
  ScrollDepthTracker({
    required CaptureSink sink,
    required CurrentScreenTracker tracker,
  }) : _sink = sink,
       _tracker = tracker;

  final CaptureSink _sink;
  final CurrentScreenTracker _tracker;

  // Deepest fraction (0..1) seen on the current screen since the last flush.
  double _max = 0;

  /// Records one scroll position as a fraction 0..1 of the scrollable extent.
  /// O(1): a bounds check and a single `max` assignment — no allocation.
  void record(double fraction) {
    if (fraction <= _max) return;
    _max = fraction < 0 ? 0 : (fraction > 1 ? 1 : fraction);
  }

  /// Screen-transition listener: flush the [previous] screen's depth, reset.
  void onScreen(String? previous, String? next) {
    _flush(previous);
    _max = 0;
  }

  /// Emits the accumulated depth for [screen], if any bucket was crossed.
  void _flush(String? screen) {
    if (screen == null) return;
    final bucket = _bucketFor(_max);
    if (bucket == null) return;
    _sink.emit(
      type: EventType.auto,
      name: 'scroll_depth',
      props: {'depth_pct': bucket},
      screen: screen,
    );
  }

  /// The highest crossed bucket for a fraction, or null if none (< 25%).
  int? _bucketFor(double fraction) {
    final pct = (fraction * 100).round();
    int? crossed;
    for (final bucket in scrollDepthBuckets) {
      if (pct >= bucket) crossed = bucket;
    }
    return crossed;
  }

  /// Flushes the current screen's depth (call on teardown so the last screen's
  /// scroll is not lost).
  void dispose() => _flush(_tracker.current);
}
