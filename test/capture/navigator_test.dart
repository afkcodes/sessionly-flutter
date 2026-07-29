import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

import 'support.dart';

void main() {
  late RecordingSink sink;
  late CurrentScreenTracker tracker;
  late SessionlyNavigatorObserver observer;

  setUp(() {
    sink = RecordingSink();
    tracker = CurrentScreenTracker();
    final runtime = CaptureRuntime.forTesting(
      sink: sink,
      config: testConfig(),
      tracker: tracker,
    );
    observer = SessionlyNavigatorObserver(runtime: runtime);
  });

  // NoSplash keeps the button tap from instantiating the Material ink ripple,
  // which loads `ink_sparkle.frag` — a bundled shader whose runtime-stages
  // format version is engine-dependent and unrelated to what this test asserts
  // (navigation edges). Disabling the splash makes the test deterministic
  // across Flutter engine builds without weakening the tap→navigate flow.
  Widget app() => MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    navigatorObservers: [observer],
    initialRoute: '/',
    routes: {
      '/': (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('to-details'),
            onPressed: () => Navigator.of(context).pushNamed('/details'),
            child: const Text('Open'),
          ),
        ),
      ),
      '/details': (_) => const Scaffold(body: Text('Details')),
    },
  );

  testWidgets('push emits screen_view with the previous-screen edge', (
    tester,
  ) async {
    await tester.pumpWidget(app());

    // Initial route.
    expect(sink.named('screen_view'), hasLength(1));
    expect(sink.named('screen_view').single.screen, '/');
    expect(sink.named('screen_view').single.props['previous_screen'], isNull);
    expect(tracker.current, '/');

    await tester.tap(find.byKey(const Key('to-details')));
    await tester.pumpAndSettle();

    final views = sink.named('screen_view').toList();
    expect(views, hasLength(2));
    expect(views[1].screen, '/details');
    expect(views[1].props['previous_screen'], '/');
    expect(views[1].props['nav_type'], 'push');
    expect(tracker.current, '/details');
  });

  testWidgets('pop emits a navigation event and reveals the prior screen', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('to-details')));
    await tester.pumpAndSettle();
    sink.events.clear();

    Navigator.of(tester.element(find.text('Details'))).pop();
    await tester.pumpAndSettle();

    expect(sink.named('navigation').single.props['nav_type'], 'pop');
    expect(sink.named('screen_view').single.screen, '/');
    expect(tracker.current, '/');
  });

  test('route name falls back to the runtime type when unnamed', () {
    expect(
      SessionlyNavigatorObserver.resolveRouteName(
        PageRouteBuilder<void>(pageBuilder: (_, _, _) => const SizedBox()),
      ),
      contains('PageRouteBuilder'),
    );
  });
}
