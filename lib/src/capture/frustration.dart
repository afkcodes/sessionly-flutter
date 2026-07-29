/// On-device frustration heuristics (docs/05 invariant 7). Pure Dart, fed by
/// the tap and navigation streams on the main isolate but strictly O(1) per
/// event: fixed-size deques, no scans that grow with history, no ML. Outputs
/// flow through the same [CaptureSink] as every other surface.
library;

import 'dart:async';
import 'dart:collection';

import 'package:sessionly_flutter/src/capture/capture_sink.dart';
import 'package:sessionly_flutter/src/capture/current_screen.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

/// One recorded tap in the rage window: a target identity, timestamp, and the
/// tap's normalized coordinates (heatmaps), when resolved.
class _TapMark {
  const _TapMark(this.targetId, this.tsMs, {this.x, this.y});
  final String targetId;
  final int tsMs;
  final double? x;
  final double? y;
}

/// Sliding-window rage/dead/nav-thrash detectors. Construct one per session and
/// feed it via [onTap] and [onScreen]; it emits frustration events itself.
class FrustrationDetectors {
  /// Wires the detectors to [sink]/[tracker]. Thresholds match docs/05 and are
  /// overridable for tests. [nowMs] and [scheduleDeadCheck] are timing seams.
  FrustrationDetectors({
    required CaptureSink sink,
    required CurrentScreenTracker tracker,
    int Function()? nowMs,
    this.rageWindowMs = 700,
    this.rageMinTaps = 3,
    this.rageCooldownMs = 2000,
    this.deadTapWindowMs = 400,
    this.navThrashWindowMs = 5000,
    Timer Function(Duration, void Function())? scheduleDeadCheck,
  }) : _sink = sink,
       _tracker = tracker,
       _nowMs = nowMs ?? _systemNowMs,
       _schedule = scheduleDeadCheck ?? Timer.new;

  static int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

  final CaptureSink _sink;
  final CurrentScreenTracker _tracker;
  final int Function() _nowMs;
  final Timer Function(Duration, void Function()) _schedule;

  /// Max age (ms) of taps counted toward a rage burst.
  final int rageWindowMs;

  /// Taps on one target within [rageWindowMs] that trigger a rage_tap.
  final int rageMinTaps;

  /// Per-target suppression (ms) after a rage_tap fires.
  final int rageCooldownMs;

  /// Grace period (ms) a non-interactive tap waits for a nav before dead_tap.
  final int deadTapWindowMs;

  /// Window (ms) an A→B→A→B route oscillation must fall inside for nav_thrash.
  final int navThrashWindowMs;

  // Fixed-capacity ring of recent taps; capacity ≥ any realistic rage burst.
  final Queue<_TapMark> _recentTaps = Queue<_TapMark>();
  static const int _maxRecentTaps = 16;
  final Map<String, int> _rageCooldownUntil = <String, int>{};

  Timer? _deadTimer;

  // Last four route names + their times, for the oscillation check.
  final Queue<String> _navNames = Queue<String>();
  final Queue<int> _navTimes = Queue<int>();
  static const int _navHistory = 4;

  /// Feeds a resolved tap. [targetId] is the stable identity string;
  /// [interactive] is `false` when the walk found no button/gesture handler.
  /// [x]/[y] are the tap's normalized coordinates (0..1), when resolved.
  void onTap({
    required String targetId,
    required bool interactive,
    double? x,
    double? y,
  }) {
    final now = _nowMs();
    _recordRage(targetId, now, x, y);
    if (!interactive) _armDeadTap(targetId, x, y);
  }

  void _recordRage(String targetId, int now, double? x, double? y) {
    _recentTaps.addLast(_TapMark(targetId, now, x: x, y: y));
    while (_recentTaps.length > _maxRecentTaps) {
      _recentTaps.removeFirst();
    }
    while (_recentTaps.isNotEmpty &&
        now - _recentTaps.first.tsMs > rageWindowMs) {
      _recentTaps.removeFirst();
    }
    var count = 0;
    for (final mark in _recentTaps) {
      if (mark.targetId == targetId) count++;
    }
    if (count < rageMinTaps) return;
    final until = _rageCooldownUntil[targetId];
    if (until != null && now < until) return;
    _rageCooldownUntil[targetId] = now + rageCooldownMs;
    _pruneCooldowns(now);
    _sink.emit(
      type: EventType.frustration,
      name: 'rage_tap',
      props: {'target': targetId, 'count': count, 'x': ?x, 'y': ?y},
      screen: _tracker.current,
    );
  }

  void _pruneCooldowns(int now) {
    _rageCooldownUntil.removeWhere((_, until) => until <= now);
  }

  void _armDeadTap(String targetId, double? x, double? y) {
    _deadTimer?.cancel();
    final screenAtTap = _tracker.current;
    _deadTimer = _schedule(Duration(milliseconds: deadTapWindowMs), () {
      _deadTimer = null;
      // Fired without an intervening nav → the tap went nowhere.
      if (_tracker.current != screenAtTap) return;
      _sink.emit(
        type: EventType.frustration,
        name: 'dead_tap',
        props: {'target': targetId, 'x': ?x, 'y': ?y},
        screen: screenAtTap,
      );
    });
  }

  /// Feeds a route transition. Cancels any pending dead_tap (a nav happened)
  /// and checks for an A→B→A→B oscillation.
  void onScreen(String? previous, String? next) {
    _deadTimer?.cancel();
    _deadTimer = null;
    if (next == null) return;
    _recordNav(next, _nowMs());
  }

  void _recordNav(String name, int now) {
    _navNames.addLast(name);
    _navTimes.addLast(now);
    while (_navNames.length > _navHistory) {
      _navNames.removeFirst();
      _navTimes.removeFirst();
    }
    if (_navNames.length < _navHistory) return;
    final n = _navNames.toList();
    final t = _navTimes.toList();
    final withinWindow = now - t.first <= navThrashWindowMs;
    final oscillates = n[0] == n[2] && n[1] == n[3] && n[0] != n[1];
    if (!withinWindow || !oscillates) return;
    _navNames.clear();
    _navTimes.clear();
    _sink.emit(
      type: EventType.frustration,
      name: 'nav_thrash',
      props: {'from': n[0], 'to': n[1]},
      screen: _tracker.current,
    );
  }

  /// Cancels any pending timer. Call on shutdown.
  void dispose() {
    _deadTimer?.cancel();
    _deadTimer = null;
  }
}
