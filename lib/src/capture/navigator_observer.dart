/// Screen capture. Drop [SessionlyNavigatorObserver] into
/// `MaterialApp.navigatorObservers` (or `CupertinoApp` / `WidgetsApp`) and every
/// route change becomes a `screen_view` with a previous-screen edge for path
/// analysis, plus `navigation` events on pop/replace.
///
/// go_router: it drives the same [Navigator] under the hood, so adding this to
/// `GoRouter(observers: [SessionlyNavigatorObserver()])` works unchanged — the
/// observer sees go_router's pages as ordinary routes.
library;

import 'package:flutter/widgets.dart';
import 'package:sessionly_flutter/src/capture/capture_sink.dart';
import 'package:sessionly_flutter/src/capture/runtime.dart';
import 'package:sessionly_flutter/src/config.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

/// Records screen views and navigation edges. Bind it explicitly (tests) or let
/// it resolve the ambient [CaptureRuntime] at callback time (app code).
class SessionlyNavigatorObserver extends NavigatorObserver {
  /// [runtime] overrides the ambient runtime in tests; app code omits it.
  SessionlyNavigatorObserver({CaptureRuntime? runtime}) : _explicit = runtime;

  final CaptureRuntime? _explicit;
  ScreenLoadTimer? _loadTimer;

  CaptureRuntime? get _runtime => _explicit ?? CaptureRuntime.current;

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    _transition(route, navType: 'push', navigationEvent: false);
  }

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) {
    _transition(previousRoute, navType: 'pop', navigationEvent: true);
  }

  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) {
    _transition(newRoute, navType: 'replace', navigationEvent: true);
  }

  void _transition(
    Route<Object?>? route, {
    required String navType,
    required bool navigationEvent,
  }) {
    final runtime = _runtime;
    if (runtime == null) return;
    try {
      final tracker = runtime.tracker;
      final previous = tracker.current;
      final screen = resolveRouteName(route);
      runtime.sink.emit(
        type: EventType.auto,
        name: 'screen_view',
        props: {'previous_screen': previous, 'nav_type': navType},
        screen: screen,
      );
      if (navigationEvent) {
        runtime.sink.emit(
          type: EventType.auto,
          name: 'navigation',
          props: {'from': previous, 'to': screen, 'nav_type': navType},
          screen: screen,
        );
      }
      // Update the shared tracker last so `previous_screen` is correct and the
      // frustration nav listener sees the transition.
      tracker.update(screen);
      if (navType == 'push') _beginLoadTimer(runtime, screen);
    } on Object {
      // Never break navigation over analytics (Rule 0.3).
    }
  }

  void _beginLoadTimer(CaptureRuntime runtime, String? screen) {
    if (screen == null) return;
    (_loadTimer ??= ScreenLoadTimer(
      sink: runtime.sink,
      config: runtime.config,
    )).begin(screen);
  }

  /// Resolves a route's display name: its `settings.name` when set, else its
  /// runtime type — never any user content (docs/05 PII).
  static String? resolveRouteName(Route<Object?>? route) {
    if (route == null) return null;
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) return name;
    return route.runtimeType.toString();
  }
}

/// Times route-push → first stable frame and emits `slow_screen_load` only when
/// the load exceeds [SessionlyConfig.slowScreenLoadMs]. A single post-frame
/// callback per push — zero per-frame cost when idle.
class ScreenLoadTimer {
  /// Emits through [sink]; [binding] and [nowMs] are test seams.
  ScreenLoadTimer({
    required CaptureSink sink,
    required SessionlyConfig config,
    WidgetsBinding? binding,
    int Function()? nowMs,
  }) : _sink = sink,
       _config = config,
       _binding = binding ?? WidgetsBinding.instance,
       _nowMs = nowMs ?? _systemNowMs;

  static int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

  final CaptureSink _sink;
  final SessionlyConfig _config;
  final WidgetsBinding _binding;
  final int Function() _nowMs;

  /// Starts timing the load of [screen].
  void begin(String screen) {
    final startedAt = _nowMs();
    _binding.addPostFrameCallback((_) {
      final elapsed = _nowMs() - startedAt;
      if (elapsed <= _config.slowScreenLoadMs) return;
      _sink.emit(
        type: EventType.perf,
        name: 'slow_screen_load',
        props: {'load_ms': elapsed},
        screen: screen,
      );
    });
  }
}
