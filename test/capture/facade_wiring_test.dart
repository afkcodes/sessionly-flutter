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

SessionlyConfig config(AutoCapture auto) => SessionlyConfig(
  writeKey: 'sly_w_test',
  endpoint: Uri.parse('https://fp.example.com'),
  autoCapture: auto,
);

Iterable<String> names(List<Map<String, Object?>> records) =>
    records.map((r) => r[RecordKey.name]).whereType<String>();

void main() {
  tearDown(Sessionly.shutdown);

  testWidgets('init installs surfaces and honors enabled flags', (
    tester,
  ) async {
    final host = _RecordingHost();
    await Sessionly.init(
      config(const AutoCapture(perf: false)),
      host: host,
      spawnWatchdog: false,
      drainInterval: const Duration(days: 1),
    );

    expect(CaptureRuntime.current, isNotNull);
    expect(CaptureRuntime.current!.lifecycle, isNotNull);
    expect(CaptureRuntime.current!.errors, isNotNull);
    expect(CaptureRuntime.current!.frame, isNull, reason: 'perf disabled');

    await Sessionly.flush();
    expect(names(host.records), contains('app_open'));
    // first_open is synthesized by the engine sessionizer, not the capture
    // layer — so the raw capture stream must not carry it (double-emit guard).
    expect(names(host.records), isNot(contains('first_open')));
    await Sessionly.shutdown(); // cancel the drain timer within the test body
  });

  testWidgets('AutoCapture.none installs no surfaces', (tester) async {
    final host = _RecordingHost();
    await Sessionly.init(
      config(AutoCapture.none),
      host: host,
      spawnWatchdog: false,
      drainInterval: const Duration(days: 1),
    );

    final runtime = CaptureRuntime.current!;
    expect(runtime.lifecycle, isNull);
    expect(runtime.errors, isNull);
    expect(runtime.frame, isNull);
    expect(runtime.frustration, isNull);
    await Sessionly.shutdown();
  });
}
