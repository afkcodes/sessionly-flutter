import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingSink sink;
  late CurrentScreenTracker tracker;

  setUp(() {
    sink = RecordingSink();
    tracker = CurrentScreenTracker()..update('Home');
  });

  test('install emits app_open on a fresh device', () {
    LifecycleCapture(sink: sink, tracker: tracker)
      ..install()
      ..dispose();

    expect(sink.named('app_open'), hasLength(1));
    expect(sink.named('app_open').single.type, EventType.lifecycle);
  });

  test(
    'capture layer never emits first_open (engine sessionizer owns it)',
    () {
      // Two inits (relaunches): the capture surface must stay silent on
      // first_open; a second owner here is what double-counted the install.
      LifecycleCapture(sink: sink, tracker: tracker)
        ..install()
        ..dispose();
      LifecycleCapture(sink: sink, tracker: tracker)
        ..install()
        ..dispose();

      expect(sink.named('app_open'), hasLength(2));
      expect(sink.named('first_open'), isEmpty);
    },
  );

  test('foreground/background edges emit and background flushes', () {
    var flushes = 0;
    LifecycleCapture(
        sink: sink,
        tracker: tracker,
        flushHint: () async => flushes++,
      )
      ..install()
      ..handleStateChange(AppLifecycleState.paused)
      ..handleStateChange(AppLifecycleState.paused) // no dup
      ..handleStateChange(AppLifecycleState.resumed)
      ..dispose();

    expect(sink.named('app_background'), hasLength(1));
    expect(sink.named('app_foreground'), hasLength(1));
    expect(flushes, 1);
  });
}
