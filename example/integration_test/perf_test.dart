// Added-jank perf harness (docs/05: "0 additional janky frames vs baseline").
//
// Runs the identical journey TWICE against the real app on a real device —
// once with the SDK disabled (baseline) and once enabled — collecting frame
// timings directly via SchedulerBinding.addTimingsCallback (no VM-service round
// trip, unlike watchPerformance), and asserts the enabled run adds no more than
// one janky build frame over baseline.
//
// Device, profile mode (real codegen). `flutter test` has no --profile, so use
// flutter drive:
//   cd sdks/flutter/example
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/perf_test.dart -d <device> --profile
//
// It lives under integration_test/, which `flutter test` does NOT run by
// default, so it never interferes with the unit-test CI gate.
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_example/main.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';
import 'package:integration_test/integration_test.dart';

import 'journey.dart';

/// 60 fps frame budget in microseconds. A build longer than this is "janky".
const int kFrameBudgetMicros = 16667;

/// docs/05 tolerance: the enabled run may add at most this many janky build
/// frames over baseline (measurement-noise headroom; the target is 0).
const int kJankTolerance = 1;

class _FrameStats {
  _FrameStats(
    this.janky,
    this.avgBuildMs,
    this.worstBuildMs,
    this.avgRasterMs,
    this.worstRasterMs,
    this.frames,
  );
  final int janky;
  final double avgBuildMs;
  final double worstBuildMs;
  final double avgRasterMs;
  final double worstRasterMs;
  final int frames;
}

_FrameStats _summarize(List<FrameTiming> t) {
  if (t.isEmpty) return _FrameStats(0, 0, 0, 0, 0, 0);
  var janky = 0;
  var sumBuild = 0.0;
  var worstBuild = 0.0;
  var sumRaster = 0.0;
  var worstRaster = 0.0;
  for (final f in t) {
    final b = f.buildDuration.inMicroseconds / 1000.0;
    final r = f.rasterDuration.inMicroseconds / 1000.0;
    if (f.buildDuration.inMicroseconds > kFrameBudgetMicros) janky++;
    sumBuild += b;
    sumRaster += r;
    if (b > worstBuild) worstBuild = b;
    if (r > worstRaster) worstRaster = r;
  }
  return _FrameStats(
    janky,
    sumBuild / t.length,
    worstBuild,
    sumRaster / t.length,
    worstRaster,
    t.length,
  );
}

Future<void> _init({required bool enabled}) async {
  final base = ExampleConfig.fromEnvironment();
  await Sessionly.init(
    SessionlyConfig(
      writeKey: base.writeKey,
      endpoint: Uri.parse(base.endpoint),
      enabled: enabled,
      flushIntervalSeconds: 5,
      flushBatchSize: 10,
    ),
  );
}

Future<_FrameStats> _runOnce(
  WidgetTester tester, {
  required bool enabled,
}) async {
  await _init(enabled: enabled);
  await tester.pumpWidget(const SessionlyExampleApp());
  await tester.pumpAndSettle();

  final collected = <FrameTiming>[];
  void listener(List<FrameTiming> timings) => collected.addAll(timings);
  SchedulerBinding.instance.addTimingsCallback(listener);

  await runJourney(tester);
  // Bounded settle (no pumpAndSettle — the IME/animation can defeat "idle").
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  // FrameTiming is reported asynchronously and in batches — give the engine a
  // moment to flush the last frames' timings before we stop listening.
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
  await tester.pump();

  SchedulerBinding.instance.removeTimingsCallback(listener);
  await Sessionly.shutdown();
  return _summarize(collected);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('enabled run adds <= 1 janky frame vs disabled baseline', (
    tester,
  ) async {
    final baseline = await _runOnce(tester, enabled: false);
    final enabled = await _runOnce(tester, enabled: true);
    final added = enabled.janky - baseline.janky;

    debugPrint(
      '\n=== SESSIONLY PERF (added jank) ===\n'
      'frames sampled base/enabled : ${baseline.frames} / ${enabled.frames}\n'
      'janky build frames base/en  : ${baseline.janky} / ${enabled.janky}\n'
      'ADDED janky build frames    : $added (tolerance $kJankTolerance)\n'
      'avg build ms  base/enabled  : '
      '${baseline.avgBuildMs.toStringAsFixed(2)} / '
      '${enabled.avgBuildMs.toStringAsFixed(2)}\n'
      'worst build ms base/enabled : '
      '${baseline.worstBuildMs.toStringAsFixed(2)} / '
      '${enabled.worstBuildMs.toStringAsFixed(2)}\n'
      'avg raster ms base/enabled  : '
      '${baseline.avgRasterMs.toStringAsFixed(2)} / '
      '${enabled.avgRasterMs.toStringAsFixed(2)}\n'
      'worst raster ms base/enabled: '
      '${baseline.worstRasterMs.toStringAsFixed(2)} / '
      '${enabled.worstRasterMs.toStringAsFixed(2)}\n'
      '===================================',
    );

    expect(baseline.frames, greaterThan(0), reason: 'no frames sampled');
    expect(
      added,
      lessThanOrEqualTo(kJankTolerance),
      reason: 'SDK must add ~0 janky frames (docs/05)',
    );
  });
}
