import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

class _RecordingHost implements EngineHost {
  final List<Map<String, Object?>> records = [];

  @override
  void submit(List<Map<String, Object?>> batch) => records.addAll(batch);

  @override
  Future<void> flush() async {}

  @override
  Future<void> shutdown() async {}
}

// AutoCapture.none so no surface emits lifecycle/etc. events into the gate,
// keeping the capture counters deterministic for these assertions.
SessionlyConfig config({bool enabled = true}) => SessionlyConfig(
  writeKey: 'sly_w_test',
  endpoint: Uri.parse('https://fp.example.com'),
  autoCapture: AutoCapture.none,
  enabled: enabled,
);

// NOTE: these tests shut the SDK down in-body rather than via
// `tearDown(Sessionly.shutdown)`. Under `testWidgets`' fake-async, tearing down
// a *disabled* SDK (whose teardown is pure microtask work) can stall the
// harness; an in-body awaited shutdown avoids that and is just as thorough.
void main() {
  testWidgets('enabled:false is a no-op and installs no surfaces', (
    tester,
  ) async {
    final host = _RecordingHost();
    await Sessionly.init(
      config(enabled: false),
      host: host,
      spawnWatchdog: false,
      drainInterval: const Duration(days: 1),
    );

    Sessionly.track('should_be_dropped');
    Sessionly.identify('u1');
    Sessionly.screen('Home');
    await Sessionly.flush();

    expect(
      host.records,
      isEmpty,
      reason: 'kill switch drops main-thread capture',
    );
    expect(CaptureRuntime.current, isNull, reason: 'no surfaces installed');
    final stats = Sessionly.debugStats();
    expect(stats['captured'], 0);
    expect(stats['enabled'], 0);

    await Sessionly.shutdown();
  });

  testWidgets('debugStats reflects captured/buffered counts when enabled', (
    tester,
  ) async {
    final host = _RecordingHost();
    await Sessionly.init(
      config(),
      host: host,
      spawnWatchdog: false,
      drainInterval: const Duration(days: 1),
    );

    Sessionly.track('a');
    Sessionly.track('b');
    var stats = Sessionly.debugStats();
    expect(stats['enabled'], 1);
    expect(stats['captured'], 2);
    expect(stats['buffered'], 2, reason: 'not drained yet');

    await Sessionly.flush();
    stats = Sessionly.debugStats();
    expect(stats['captured'], 2, reason: 'captured is monotonic');
    expect(stats['buffered'], 0, reason: 'flush drained the buffer');

    await Sessionly.shutdown();
  });
}
