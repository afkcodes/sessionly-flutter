import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

import 'support.dart';

/// A [FrameTiming] whose total span is [ms] milliseconds.
FrameTiming frame(int ms) => FrameTiming(
  vsyncStart: 0,
  buildStart: 0,
  buildFinish: 0,
  rasterStart: 0,
  rasterFinish: ms * 1000,
  rasterFinishWallTime: 0,
);

void main() {
  late RecordingSink sink;
  late CurrentScreenTracker tracker;

  FrameTimingCapture build() =>
      FrameTimingCapture(sink: sink, tracker: tracker);

  setUp(() {
    sink = RecordingSink();
    tracker = CurrentScreenTracker()..update('Feed');
  });

  test('a burst of janky frames aggregates into one slow_frame_burst', () {
    build()
      ..onTimings([frame(20), frame(30), frame(25), frame(8)])
      ..drain();
    final burst = sink.named('slow_frame_burst').single;
    expect(burst.type, EventType.perf);
    expect(burst.props['count'], 3);
    expect(burst.props['worst_ms'], 30);
    expect(burst.screen, 'Feed');
  });

  test('fewer than the burst minimum emits nothing', () {
    build()
      ..onTimings([frame(20), frame(22)])
      ..drain();
    expect(sink.named('slow_frame_burst'), isEmpty);
  });

  test('a frame over 700 ms is a frozen_frame', () {
    build()
      ..onTimings([frame(9), frame(820)])
      ..drain();
    final frozen = sink.named('frozen_frame').single;
    expect(frozen.props['count'], 1);
    expect(frozen.props['worst_ms'], 820);
  });

  test('drain resets the window', () {
    build()
      ..onTimings([frame(20), frame(20), frame(20)])
      ..drain()
      ..drain();
    expect(sink.named('slow_frame_burst'), hasLength(1));
  });

  test('processing 1000 frames stays well under budget', () {
    final capture = build();
    final frames = List.generate(1000, (i) => frame(i % 40));
    final sw = Stopwatch()..start();
    capture.onTimings(frames);
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(100));
  });
}
