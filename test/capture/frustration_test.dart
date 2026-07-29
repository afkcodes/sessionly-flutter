import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

import 'support.dart';

/// A [Timer] the test fires by hand, honoring cancellation.
class FakeTimer implements Timer {
  FakeTimer(this._callback);
  final void Function() _callback;
  bool _cancelled = false;

  void fire() {
    if (!_cancelled) _callback();
  }

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => 0;
}

void main() {
  late RecordingSink sink;
  late CurrentScreenTracker tracker;
  late int now;
  FakeTimer? lastDeadTimer;

  FrustrationDetectors build() => FrustrationDetectors(
    sink: sink,
    tracker: tracker,
    nowMs: () => now,
    scheduleDeadCheck: (_, cb) => lastDeadTimer = FakeTimer(cb),
  );

  setUp(() {
    sink = RecordingSink();
    tracker = CurrentScreenTracker()..update('Home');
    now = 1000;
    lastDeadTimer = null;
  });

  group('rage_tap', () {
    test('3 taps on one target within 700 ms fire exactly one rage_tap', () {
      final d = build();
      for (var i = 0; i < 3; i++) {
        d.onTap(targetId: 'Button/save', interactive: true);
        now += 100;
      }
      final rage = sink.named('rage_tap').toList();
      expect(rage, hasLength(1));
      expect(rage.single.type, EventType.frustration);
      expect(rage.single.props['target'], 'Button/save');
      expect(rage.single.props['count'], 3);
      expect(rage.single.screen, 'Home');
    });

    test('cooldown suppresses a second rage within 2 s', () {
      final d = build();
      for (var i = 0; i < 5; i++) {
        d.onTap(targetId: 'Button/save', interactive: true);
        now += 100;
      }
      expect(sink.named('rage_tap'), hasLength(1));
    });

    test('taps spread past the 700 ms window never rage', () {
      final d = build();
      for (var i = 0; i < 5; i++) {
        d.onTap(targetId: 'Button/save', interactive: true);
        now += 400;
      }
      expect(sink.named('rage_tap'), isEmpty);
    });

    test('rage_tap carries the triggering tap coordinates', () {
      final d = build();
      for (var i = 0; i < 3; i++) {
        d.onTap(targetId: 'Button/save', interactive: true, x: 0.4, y: 0.6);
        now += 100;
      }
      final rage = sink.named('rage_tap').single;
      expect(rage.props['x'], 0.4);
      expect(rage.props['y'], 0.6);
    });
  });

  group('dead_tap', () {
    test('non-interactive tap with no nav within window fires dead_tap', () {
      build().onTap(targetId: 'Text/label', interactive: false);
      expect(lastDeadTimer, isNotNull);
      lastDeadTimer!.fire();
      final dead = sink.named('dead_tap').toList();
      expect(dead, hasLength(1));
      expect(dead.single.props['target'], 'Text/label');
    });

    test('interactive tap never arms a dead_tap', () {
      build().onTap(targetId: 'Button/go', interactive: true);
      expect(lastDeadTimer, isNull);
    });

    test('dead_tap carries the tap coordinates', () {
      build().onTap(targetId: 'Text/label', interactive: false, x: 0.1, y: 0.2);
      lastDeadTimer!.fire();
      final dead = sink.named('dead_tap').single;
      expect(dead.props['x'], 0.1);
      expect(dead.props['y'], 0.2);
    });

    test('a navigation before the window cancels the dead_tap', () {
      build()
        ..onTap(targetId: 'Text/label', interactive: false)
        ..onScreen('Home', 'Details'); // nav happened → cancel
      lastDeadTimer!.fire();
      expect(sink.named('dead_tap'), isEmpty);
    });
  });

  group('nav_thrash', () {
    test('A→B→A→B within 5 s fires one nav_thrash', () {
      final d = build();
      for (final screen in ['A', 'B', 'A', 'B']) {
        d.onScreen(null, screen);
        now += 200;
      }
      final thrash = sink.named('nav_thrash').toList();
      expect(thrash, hasLength(1));
      expect(thrash.single.props['from'], 'A');
      expect(thrash.single.props['to'], 'B');
    });

    test('a non-oscillating path does not thrash', () {
      final d = build();
      for (final screen in ['A', 'B', 'C', 'D']) {
        d.onScreen(null, screen);
        now += 200;
      }
      expect(sink.named('nav_thrash'), isEmpty);
    });

    test('oscillation slower than the window does not thrash', () {
      final d = build();
      for (final screen in ['A', 'B', 'A', 'B']) {
        d.onScreen(null, screen);
        now += 2000;
      }
      expect(sink.named('nav_thrash'), isEmpty);
    });
  });
}
