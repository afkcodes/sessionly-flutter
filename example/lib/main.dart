// Sessionly SDK example app: a small but real 4-screen app that is also the
// performance harness target for integration_test/perf_test.dart.
//
// Endpoint / write key / enabled come from --dart-define so the same binary can
// point at an emulator, a LAN ingest, or run with the SDK disabled:
//
//   flutter run \
//     --dart-define=FP_ENDPOINT=http://192.168.0.250:8788 \
//     --dart-define=FP_WRITE_KEY=sly_w_xxx
//
// Defaults target the Android emulator loopback (10.0.2.2).
import 'package:flutter/material.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

import 'debug_overlay.dart';
import 'screens.dart';

/// Runtime configuration sourced from `--dart-define`.
class ExampleConfig {
  const ExampleConfig({
    required this.endpoint,
    required this.writeKey,
    required this.enabled,
  });

  /// Reads FP_ENDPOINT / FP_WRITE_KEY / FP_ENABLED from the compile environment.
  factory ExampleConfig.fromEnvironment() {
    return const ExampleConfig(
      endpoint: String.fromEnvironment(
        'FP_ENDPOINT',
        defaultValue: 'http://10.0.2.2:8788',
      ),
      writeKey: String.fromEnvironment(
        'FP_WRITE_KEY',
        defaultValue: 'sly_w_demo',
      ),
      enabled: bool.fromEnvironment('FP_ENABLED', defaultValue: true),
    );
  }

  final String endpoint;
  final String writeKey;
  final bool enabled;

  /// The SDK config this maps to.
  SessionlyConfig toSessionlyConfig() => SessionlyConfig(
    writeKey: writeKey,
    endpoint: Uri.parse(endpoint),
    enabled: enabled,
    // Flush aggressively so the on-device e2e sees events within the 60 s SLA.
    flushIntervalSeconds: 5,
    flushBatchSize: 10,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = ExampleConfig.fromEnvironment();
  // init is cheap on the main isolate (< 5 ms); heavy work is async off-frame.
  await Sessionly.init(config.toSessionlyConfig());
  runApp(const SessionlyExampleApp());
}

/// The instrumented app widget. Kept separate from [main] so the perf harness
/// can pump it after driving its own [Sessionly.init].
class SessionlyExampleApp extends StatelessWidget {
  const SessionlyExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    // SessionlyRoot is the tap-capture install point; the observer captures
    // screen views. Both resolve the ambient runtime installed by init.
    return SessionlyRoot(
      child: MaterialApp(
        title: 'Sessionly Example',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        navigatorObservers: [SessionlyNavigatorObserver()],
        initialRoute: Routes.home,
        routes: {
          Routes.home: (_) => const HomeScreen(),
          Routes.list: (_) => const ListScreen(),
          Routes.form: (_) => const FormScreen(),
          Routes.heavy: (_) => const HeavyScreen(),
        },
        builder: (context, child) =>
            DebugStatsOverlay(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
