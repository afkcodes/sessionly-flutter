/// The ambient wiring that ties every auto-capture surface together and makes
/// them reachable from the user-constructed `SessionlyNavigatorObserver` and
/// `SessionlyRoot` without threading engine handles through app code.
///
/// `Sessionly.init` builds one [CaptureRuntime] and parks it in
/// [CaptureRuntime.current]; the observer and root read it late (at callback
/// time) so they work even when constructed before init completes.
library;

import 'package:flutter/foundation.dart';
import 'package:sessionly_flutter/src/capture/capture_sink.dart';
import 'package:sessionly_flutter/src/capture/current_screen.dart';
import 'package:sessionly_flutter/src/capture/errors.dart';
import 'package:sessionly_flutter/src/capture/frame_timing.dart';
import 'package:sessionly_flutter/src/capture/frustration.dart';
import 'package:sessionly_flutter/src/capture/input_capture.dart';
import 'package:sessionly_flutter/src/capture/lifecycle.dart';
import 'package:sessionly_flutter/src/capture/main_thread_watchdog.dart';
import 'package:sessionly_flutter/src/capture/scroll_depth.dart';
import 'package:sessionly_flutter/src/config.dart';

/// Holds the live surfaces for one SDK session and drives install/dispose.
class CaptureRuntime {
  CaptureRuntime._({
    required this.sink,
    required this.tracker,
    required this.config,
    this.frustration,
    this.errors,
    this.frame,
    this.watchdog,
    this.lifecycle,
    this.scrollDepth,
    this.inputs,
  });

  /// Builds a runtime wired to a caller-supplied [sink]/[tracker]/[frustration]
  /// with no OS surfaces installed. For widget tests of the observer and root.
  @visibleForTesting
  factory CaptureRuntime.forTesting({
    required CaptureSink sink,
    required SessionlyConfig config,
    CurrentScreenTracker? tracker,
    FrustrationDetectors? frustration,
  }) => CaptureRuntime._(
    sink: sink,
    tracker: tracker ?? CurrentScreenTracker(),
    config: config,
    frustration: frustration,
  );

  /// The runtime the ambient surfaces bind to, or `null` when uninstalled.
  static CaptureRuntime? current;

  /// The shared emit choke point.
  final CaptureSink sink;

  /// The shared current-screen holder.
  final CurrentScreenTracker tracker;

  /// The active engine config.
  final SessionlyConfig config;

  /// Frustration windows, or `null` when neither taps nor screens are on.
  final FrustrationDetectors? frustration;

  /// Chained error handlers, or `null` when errors are off.
  final SessionlyErrorHandlers? errors;

  /// Frame-timing capture, or `null` when perf is off.
  final FrameTimingCapture? frame;

  /// ANR watchdog, or `null` when perf/spawn is off.
  final MainThreadWatchdog? watchdog;

  /// Lifecycle listener, or `null` when lifecycle is off.
  final LifecycleCapture? lifecycle;

  /// Per-screen scroll-depth tracker, or `null` when scroll capture is off.
  final ScrollDepthTracker? scrollDepth;

  /// Text-input focus/abandon capture, or `null` when input capture is off.
  final InputFocusCapture? inputs;

  /// Builds and installs the surfaces enabled by [config]'s [AutoCapture], then
  /// publishes the result to [current]. Every install is best-effort — a
  /// failing surface is skipped, never fatal to the others (Rule 0.3).
  static Future<CaptureRuntime> install({
    required CaptureSink sink,
    required SessionlyConfig config,
    int Function()? nowMs,
    Future<void> Function()? flushHint,
    CurrentScreenTracker? tracker,
    bool spawnWatchdog = true,
  }) async {
    final auto = config.autoCapture;
    final screen = tracker ?? CurrentScreenTracker();

    FrustrationDetectors? frustration;
    if (auto.taps || auto.screens) {
      frustration = _guard(() {
        final detector = FrustrationDetectors(
          sink: sink,
          tracker: screen,
          nowMs: nowMs,
        );
        screen.addListener(detector.onScreen);
        return detector;
      });
    }

    final errors = auto.errors
        ? _guard(
            () => SessionlyErrorHandlers(
              sink: sink,
              config: config,
              nowScreen: () => screen.current,
            )..install(),
          )
        : null;

    final frame = auto.perf
        ? _guard(
            () => FrameTimingCapture(sink: sink, tracker: screen)..install(),
          )
        : null;

    LifecycleCapture? lifecycle;
    if (auto.lifecycle) {
      lifecycle = _guard(
        () => LifecycleCapture(
          sink: sink,
          tracker: screen,
          flushHint: flushHint,
        )..install(),
      );
    }

    MainThreadWatchdog? watchdog;
    if (auto.perf && spawnWatchdog) {
      watchdog = await _guardAsync(() async {
        final dog = MainThreadWatchdog(sink: sink, tracker: screen);
        await dog.install();
        return dog;
      });
    }

    ScrollDepthTracker? scrollDepth;
    if (auto.scroll) {
      scrollDepth = _guard(() {
        final t = ScrollDepthTracker(sink: sink, tracker: screen);
        screen.addListener(t.onScreen);
        return t;
      });
    }

    InputFocusCapture? inputs;
    if (auto.inputs) {
      inputs = _guard(() {
        final i = InputFocusCapture(sink: sink, tracker: screen, nowMs: nowMs)
          ..install();
        return i;
      });
    }

    return current = CaptureRuntime._(
      sink: sink,
      tracker: screen,
      config: config,
      frustration: frustration,
      errors: errors,
      frame: frame,
      watchdog: watchdog,
      lifecycle: lifecycle,
      scrollDepth: scrollDepth,
      inputs: inputs,
    );
  }

  static T? _guard<T>(T Function() body) {
    try {
      return body();
    } on Object {
      return null;
    }
  }

  static Future<T?> _guardAsync<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Object {
      return null;
    }
  }

  /// Tears down every installed surface and clears [current] if it is this one.
  Future<void> dispose() async {
    if (identical(current, this)) current = null;
    final detector = frustration;
    if (detector != null) {
      tracker.removeListener(detector.onScreen);
      detector.dispose();
    }
    errors?.uninstall();
    frame?.dispose();
    watchdog?.dispose();
    lifecycle?.dispose();
    final scroll = scrollDepth;
    if (scroll != null) {
      tracker.removeListener(scroll.onScreen);
      scroll.dispose();
    }
    inputs?.dispose();
  }
}
