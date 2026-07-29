import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

void main() {
  test('reports a stall once and only after recovery-eligible echoes', () {
    final detector = WatchdogDetector();
    // Healthy round-trips report nothing.
    expect(detector.onEcho(200), isNull);
    expect(detector.onEcho(1200), isNull);
    // The first over-threshold echo reports the stall duration.
    expect(detector.onEcho(6000), 6000);
    // No spam while the same stall persists (queued echoes flush at once).
    expect(detector.onEcho(6500), isNull);
    expect(detector.onEcho(9000), isNull);
  });

  test('a fresh stall reports again once the thread has recovered', () {
    final detector = WatchdogDetector();
    expect(detector.onEcho(7000), 7000);
    expect(detector.onEcho(7000), isNull);
    expect(detector.onEcho(50), isNull); // recovered
    expect(detector.onEcho(8000), 8000); // new episode
  });
}
