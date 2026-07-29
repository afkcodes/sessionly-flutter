// On-device end-to-end driver. Runs the journey ONCE with the SDK enabled and
// pointed at a real ingest endpoint (passed via --dart-define), then flushes and
// waits so uploads settle. Server-side verification (countEvents) happens on the
// host — see PERF.md for the exact commands.
//
//   cd sdks/flutter/example
//   flutter test integration_test/e2e_test.dart -d <device> --profile \
//     --dart-define=FP_ENDPOINT=http://<LAN-IP>:8788 \
//     --dart-define=FP_WRITE_KEY=<provisioned write key>
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_example/main.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';
import 'package:integration_test/integration_test.dart';

import 'journey.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('drives the journey against a live endpoint and flushes', (
    tester,
  ) async {
    final cfg = ExampleConfig.fromEnvironment();
    debugPrint('SESSIONLY e2e -> endpoint=${cfg.endpoint}');
    await Sessionly.init(cfg.toSessionlyConfig());
    // Identify so the identity pipeline is exercised too.
    Sessionly.identify('device_e2e_user');

    await tester.pumpWidget(const SessionlyExampleApp());
    await tester.pumpAndSettle();

    await runJourney(tester);

    // Two custom markers so the host can assert exact expected counts.
    Sessionly.track('device_e2e_marker', props: {'run': 1});
    Sessionly.track('device_e2e_marker', props: {'run': 2});

    // Force an upload and give the background isolate time to drain to ingest.
    await Sessionly.flush();
    await tester.pump(const Duration(seconds: 3));
    await Sessionly.flush();

    final stats = Sessionly.debugStats();
    debugPrint('SESSIONLY e2e debugStats: $stats');
    expect(stats['captured']! > 0, isTrue);
  });
}
