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

  test(
    'a burst of >= 6 dropped frames aggregates into one slow_frame_burst',
    () {
      build()
        // Six frames past the 32ms bar (dropped a frame), one on-budget.
        ..onTimings([
          frame(40),
          frame(50),
          frame(45),
          frame(35),
          frame(60),
          frame(33),
          frame(10),
        ])
        ..drain();
      final burst = sink.named('slow_frame_burst').single;
      expect(burst.type, EventType.perf);
      expect(burst.props['count'], 6);
      expect(burst.props['worst_ms'], 60);
      expect(burst.screen, 'Feed');
    },
  );

  test('incidental slow frames below the burst minimum stay quiet', () {
    // Three dropped frames in the window is not a stutter — no event (was noise
    // at the old 16ms/3-frame bar).
    build()
      ..onTimings([frame(40), frame(50), frame(45)])
      ..drain();
    expect(sink.named('slow_frame_burst'), isEmpty);
  });

  test('a frame on the 60Hz budget is not janky', () {
    // 20ms grazes the budget but did not drop a frame at 60Hz — must not count.
    build()
      ..onTimings(List.generate(8, (_) => frame(20)))
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
      ..onTimings(List.generate(6, (_) => frame(40)))
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
