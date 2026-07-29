import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

import 'support.dart';

void main() {
  late RecordingSink sink;
  late CurrentScreenTracker tracker;
  late ScrollDepthTracker scroll;

  setUp(() {
    sink = RecordingSink();
    tracker = CurrentScreenTracker()..update('Article');
    scroll = ScrollDepthTracker(sink: sink, tracker: tracker);
  });

  test('emits the highest crossed bucket on screen exit', () {
    scroll
      ..record(0.30)
      ..record(0.80) // max stays 0.80 → bucket 75
      ..record(0.50)
      ..onScreen('Article', 'Detail');

    final events = sink.named('scroll_depth').toList();
    expect(events, hasLength(1));
    expect(events.single.type, EventType.auto);
    expect(events.single.props['depth_pct'], 75);
    expect(events.single.screen, 'Article'); // the screen being left
  });

  test('a full scroll to the bottom emits the 100 bucket', () {
    scroll
      ..record(1)
      ..onScreen('Article', 'Detail');
    expect(sink.named('scroll_depth').single.props['depth_pct'], 100);
  });

  test('scrolling under 25% emits nothing', () {
    scroll
      ..record(0.10)
      ..onScreen('Article', 'Detail');
    expect(sink.named('scroll_depth'), isEmpty);
  });

  test('depth resets after a screen exit (no bleed across screens)', () {
    scroll
      ..record(0.90)
      ..onScreen('Article', 'Detail') // emits 75 for Article
      // On Detail the user barely scrolls.
      ..record(0.05)
      ..onScreen('Detail', 'Home');
    final events = sink.named('scroll_depth').toList();
    expect(events, hasLength(1)); // only Article emitted
    expect(events.single.screen, 'Article');
  });

  test('record clamps out-of-range fractions', () {
    scroll
      ..record(5) // overscroll → clamps to 1.0
      ..onScreen('Article', 'Detail');
    expect(sink.named('scroll_depth').single.props['depth_pct'], 100);
  });

  test('dispose flushes the current screen', () {
    scroll
      ..record(0.60)
      ..dispose();
    final events = sink.named('scroll_depth').toList();
    expect(events, hasLength(1));
    expect(events.single.props['depth_pct'], 50);
    expect(events.single.screen, 'Article');
  });

  test('a null previous screen emits nothing', () {
    scroll
      ..record(0.90)
      ..onScreen(null, 'Article');
    expect(sink.named('scroll_depth'), isEmpty);
  });
}
