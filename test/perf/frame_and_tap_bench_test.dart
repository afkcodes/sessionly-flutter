/// The `dart:ui`-bound half of the micro-benchmark gate (companion to
/// `benchmark/main.dart`, which covers the pure-Dart budgets). These two paths
/// touch `dart:ui`/Flutter types (`FrameTiming`, `Offset`, `WidgetsBinding`), so
/// they run under `flutter test` — which provides the engine — rather than
/// `dart run`. Budgets (docs/05 "Flutter-specific budgets"):
///
///   - FrameTimingCapture.onTimings  mean < 0.1 ms/frame
///   - SessionlyRoot tap record+schedule (excl. post-frame walk)  < 0.5 ms
///
/// Assertions ARE the gate: a regression past budget fails `flutter test`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show FrameTiming;
import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

/// Builds one synthetic [FrameTiming] with a chosen total span in microseconds.
FrameTiming _frame(int totalMicros) {
  // vsyncStart .. rasterFinish spans totalMicros; the handler only reads
  // totalSpan (rasterFinish - vsyncStart), so the interior split is arbitrary.
  const vsyncStart = 0;
  final buildStart = totalMicros ~/ 4;
  final buildFinish = totalMicros ~/ 2;
  final rasterStart = buildFinish;
  final rasterFinish = totalMicros;
  return FrameTiming(
    vsyncStart: vsyncStart,
    buildStart: buildStart,
    buildFinish: buildFinish,
    rasterStart: rasterStart,
    rasterFinish: rasterFinish,
    rasterFinishWallTime: rasterFinish,
  );
}

double _meanMsPerFrame(void Function() body, int frames) {
  final sw = Stopwatch()..start();
  final msPerTick = 1000.0 / sw.frequency;
  final t0 = sw.elapsedTicks;
  body();
  final t1 = sw.elapsedTicks;
  return ((t1 - t0) * msPerTick) / frames;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FrameTimingCapture.onTimings mean < 0.1 ms/frame (10k frames)', () {
    final sink = _NullSink();
    final capture = FrameTimingCapture(
      sink: sink,
      tracker: CurrentScreenTracker(),
    );
    // A realistic mix: mostly good frames, some janky, a few frozen.
    final batch = <FrameTiming>[
      for (var i = 0; i < 100; i++)
        _frame(i % 20 == 0 ? 720000 : (i % 5 == 0 ? 20000 : 8000)),
    ];
    const batches = 100; // 100 batches * 100 = 10k frames
    // Warm up the JIT.
    for (var i = 0; i < 10; i++) {
      capture.onTimings(batch);
    }
    final mean = _meanMsPerFrame(() {
      for (var b = 0; b < batches; b++) {
        capture.onTimings(batch);
      }
    }, batches * batch.length);
    debugPrint(
      'onTimings mean per-frame: ${(mean * 1000).toStringAsFixed(3)} µs '
      '(budget 100 µs)',
    );
    expect(
      mean,
      lessThan(0.1),
      reason: 'addTimingsCallback budget < 0.1 ms/frame',
    );
  });

  test('ScrollDepthTracker.record p99 < 0.05 ms (100k notifications)', () {
    final tracker = ScrollDepthTracker(
      sink: _NullSink(),
      tracker: CurrentScreenTracker()..update('Article'),
    );
    const iterations = 100000;
    // Warm up the JIT.
    for (var i = 0; i < 1000; i++) {
      tracker.record((i % 100) / 100);
    }
    final samples = <double>[];
    final sw = Stopwatch()..start();
    final msPerTick = 1000.0 / sw.frequency;
    for (var i = 0; i < iterations; i++) {
      final f = (i % 100) / 100;
      final t0 = sw.elapsedTicks;
      tracker.record(f);
      final t1 = sw.elapsedTicks;
      samples.add((t1 - t0) * msPerTick);
    }
    samples.sort();
    final p99 = samples[(0.99 * (samples.length - 1)).round()];
    debugPrint(
      'scroll record p99=${(p99 * 1000).toStringAsFixed(2)} µs (budget 50 µs)',
    );
    expect(p99, lessThan(0.05), reason: 'scroll record O(1) budget < 0.05 ms');
  });

  testWidgets('tap record+schedule main-thread cost < 0.5 ms', (tester) async {
    // Install a SessionlyRoot over a large keyed button grid; measure only the
    // synchronous pointer-up handler (record position + arm one post-frame
    // callback) — NOT the post-frame identity walk, which the app never blocks
    // on. We drive the Listener's onPointerUp directly to time that path alone.
    final sink = _NullSink();
    final runtime = CaptureRuntime.forTesting(
      sink: sink,
      config: SessionlyConfig(
        writeKey: 'sly_w_test',
        endpoint: Uri.parse('https://fp.example.com'),
      ),
    );
    PointerUpEventListener? onUp;
    await tester.pumpWidget(
      SessionlyRoot(
        runtime: runtime,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: _CaptureListener(
            onFound: (cb) => onUp = cb,
            child: ListView(
              children: [
                for (var i = 0; i < 20; i++)
                  ElevatedButton(
                    key: ValueKey('btn_$i'),
                    onPressed: () {},
                    child: Text('Button $i'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(onUp, isNotNull);
    const iterations = 5000;
    final samples = <double>[];
    final sw = Stopwatch()..start();
    final msPerTick = 1000.0 / sw.frequency;
    for (var i = 0; i < iterations; i++) {
      final event = PointerUpEvent(position: Offset(100, 100 + (i % 300)));
      final t0 = sw.elapsedTicks;
      onUp!(event);
      final t1 = sw.elapsedTicks;
      samples.add((t1 - t0) * msPerTick);
    }
    samples.sort();
    final p99 = samples[(0.99 * (samples.length - 1)).round()];
    final p50 = samples[samples.length ~/ 2];
    debugPrint(
      'tap record+schedule p50=${(p50 * 1000).toStringAsFixed(2)} µs '
      'p99=${(p99 * 1000).toStringAsFixed(2)} µs (budget 500 µs)',
    );
    expect(p99, lessThan(0.5), reason: 'tap record+schedule budget < 0.5 ms');
  });
}

/// Discards every emitted event — the surfaces under test are timed, not
/// asserted on.
class _NullSink implements CaptureSink {
  @override
  void emit({
    required EventType type,
    required String name,
    Map<String, Object?> props = const {},
    String? screen,
  }) {}
}

/// Finds the nearest ambient [Listener]'s `onPointerUp` so the benchmark can
/// invoke exactly the synchronous hot path `SessionlyRoot` installs.
typedef PointerUpEventListener = void Function(PointerUpEvent event);

class _CaptureListener extends StatelessWidget {
  const _CaptureListener({required this.onFound, required this.child});

  final void Function(PointerUpEventListener) onFound;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Walk up from this element to the SessionlyRoot's Listener and hand its
    // onPointerUp to the test. Done once at build; cheap and side-effect free.
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is Listener && widget.onPointerUp != null) {
        onFound(widget.onPointerUp!);
        return false;
      }
      return true;
    });
    return child;
  }
}
