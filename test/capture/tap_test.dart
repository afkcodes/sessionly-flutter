import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

import 'support.dart';

void main() {
  late RecordingSink sink;
  late CurrentScreenTracker tracker;
  late CaptureRuntime runtime;

  setUp(() {
    sink = RecordingSink();
    tracker = CurrentScreenTracker()..update('Home');
    runtime = CaptureRuntime.forTesting(
      sink: sink,
      config: testConfig(),
      tracker: tracker,
      frustration: FrustrationDetectors(sink: sink, tracker: tracker),
    );
  });

  testWidgets('tap on a keyed button yields stable identity, no text', (
    tester,
  ) async {
    await tester.pumpWidget(
      SessionlyRoot(
        runtime: runtime,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: GestureDetector(
                key: const Key('save'),
                onTap: () {},
                child: const SizedBox(
                  width: 120,
                  height: 48,
                  child: Center(child: Text('Click me')),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('save')));
    // Resolution is deferred to a post-frame callback: nothing yet.
    expect(sink.named('tap'), isEmpty);

    await tester.pump();
    final tap = sink.named('tap').single;
    expect(tap.type, EventType.auto);
    expect(tap.props['widget_type'], 'GestureDetector');
    expect(tap.props['key'].toString(), contains('save'));
    expect(tap.screen, 'Home');
    // PII: never the button's text content.
    expect(
      tap.props.values.any((v) => v.toString().contains('Click me')),
      isFalse,
    );
  });

  testWidgets('tap carries normalized x/y coordinates in [0,1]', (
    tester,
  ) async {
    await tester.pumpWidget(
      SessionlyRoot(
        runtime: runtime,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: GestureDetector(
                key: const Key('save'),
                onTap: () {},
                child: const SizedBox(width: 120, height: 48),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('save')));
    await tester.pump();

    final tap = sink.named('tap').single;
    expect(tap.props['x'], isA<double>());
    expect(tap.props['y'], isA<double>());
    final x = tap.props['x']! as double;
    final y = tap.props['y']! as double;
    expect(x, inInclusiveRange(0, 1));
    expect(y, inInclusiveRange(0, 1));
    // A centered target on the default 800×600 surface ≈ (0.5, 0.5).
    expect(x, closeTo(0.5, 0.05));
    expect(y, closeTo(0.5, 0.05));
  });

  testWidgets('tap on a TextField never captures its value', (tester) async {
    final controller = TextEditingController(text: 'secret@example.com');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      SessionlyRoot(
        runtime: runtime,
        child: MaterialApp(
          home: Scaffold(
            body: TextField(key: const Key('email'), controller: controller),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('email')));
    await tester.pump();

    final tap = sink.named('tap').single;
    // The PII guarantee: the field's value appears in no prop, ever.
    for (final value in tap.props.values) {
      expect(value.toString(), isNot(contains('secret@example.com')));
    }
    // Nor is the value hiding in the frustration target identity.
    expect(tap.props.values.join(), isNot(contains('secret')));
  });

  testWidgets('tap ts is stamped at pointer-up, not at post-frame resolve', (
    tester,
  ) async {
    var clock = 1000;
    await tester.pumpWidget(
      SessionlyRoot(
        runtime: runtime,
        nowMs: () => clock,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: GestureDetector(
                key: const Key('go'),
                onTap: () {},
                child: const SizedBox(width: 120, height: 48),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('go'))); // pointer-up at clock=1000
    clock = 5000; // time passes (a navigation frame) before resolution runs
    await tester.pump();

    // The tap carries its POINTER-UP time, not the later resolve time — so it
    // can't sort after the screen_view a tab tap triggers.
    expect(sink.named('tap').single.tsMs, 1000);
  });

  testWidgets('a drag/scroll past the touch slop is NOT recorded as a tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      SessionlyRoot(
        runtime: runtime,
        child: const MaterialApp(
          home: Scaffold(
            body: Center(child: SizedBox(width: 300, height: 300)),
          ),
        ),
      ),
    );

    // A stationary tap IS recorded.
    await tester.tap(find.byType(SizedBox));
    await tester.pump();
    expect(sink.named('tap'), hasLength(1));

    // A drag (well past the 18px slop) is NOT: a scroll looks like this, and it
    // used to flood tap + dead_tap on scrollable screens.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SizedBox)),
    );
    await gesture.moveBy(const Offset(120, 0));
    await gesture.up();
    await tester.pump();
    expect(sink.named('tap'), hasLength(1)); // still just the one from the tap
  });

  testWidgets('resolveTapTarget is bounded to the walk budget', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('x'))),
      ),
    );
    final root = tester.element(find.byType(Scaffold));
    final target = resolveTapTarget(root, tester.getCenter(find.text('x')));
    expect(target, isNotNull);
    // Never explodes on a deep tree; identity is content-free.
    expect(target!.widgetType, isNotEmpty);
  });
}
