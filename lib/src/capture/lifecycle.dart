/// App lifecycle capture (docs/05): `AppLifecycleListener` → foreground /
/// background events, an `app_open` per launch, and a flush hint on
/// backgrounding so buffered events reach disk before the OS may suspend us.
///
/// `first_open` is deliberately NOT emitted here: the engine's `Sessionizer` is
/// the single owner of that install-once event (it must stamp it with the
/// session id it mints on cold start, and it holds the in-memory + persisted
/// latch that keeps it to exactly one per install). A second emitter on the
/// main isolate — writing a separate flag, in a separate kv store, on a
/// separate isolate — cannot coordinate with that latch and double-counts.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sessionly_flutter/src/capture/capture_sink.dart';
import 'package:sessionly_flutter/src/capture/current_screen.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

/// Observes app lifecycle transitions and emits lifecycle-type events.
class LifecycleCapture {
  /// Emits through [sink]. [flushHint] is called (fire-and-forget) on
  /// background; [tracker] stamps the screen.
  LifecycleCapture({
    required CaptureSink sink,
    required CurrentScreenTracker tracker,
    Future<void> Function()? flushHint,
  }) : _sink = sink,
       _tracker = tracker,
       _flushHint = flushHint;

  final CaptureSink _sink;
  final CurrentScreenTracker _tracker;
  final Future<void> Function()? _flushHint;

  AppLifecycleListener? _listener;
  bool _foreground = true;

  /// Emits `app_open` and registers the OS listener. `first_open` is owned by
  /// the engine `Sessionizer`, not this surface.
  void install() {
    _listener = AppLifecycleListener(onStateChange: handleStateChange);
    _sink.emit(
      type: EventType.lifecycle,
      name: 'app_open',
      screen: _tracker.current,
    );
  }

  /// Maps a raw [state] to a foreground/background edge. Public so tests can
  /// drive transitions without a live `WidgetsBinding`.
  void handleStateChange(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      _sink.emit(
        type: EventType.lifecycle,
        name: 'app_foreground',
        screen: _tracker.current,
      );
    } else {
      _sink.emit(
        type: EventType.lifecycle,
        name: 'app_background',
        screen: _tracker.current,
      );
      // Best-effort: get buffered events onto disk before suspension.
      final hint = _flushHint;
      if (hint != null) unawaited(hint());
    }
  }

  /// Removes the OS listener.
  void dispose() {
    _listener?.dispose();
    _listener = null;
  }
}
