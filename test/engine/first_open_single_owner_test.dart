// Regression test for the `first_open` double-emit race (P2-T18).
//
// Before the fix two surfaces owned `first_open`: the main-isolate
// `LifecycleCapture` (its own persisted flag) AND the engine `Sessionizer`
// (session-scoped synthesis). On a cold start both fired for a single install,
// so ClickHouse saw `first_open: 2` per device. This drives the real capture
// surface through the real engine and asserts the install-once event lands
// exactly once. Fails on the pre-fix code (delivers 2); passes after the
// capture layer stops emitting it and the sessionizer becomes the sole owner.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

const _ctx = CtxSnapshot(
  appVersion: '1.0.0',
  build: '10',
  os: 'android',
  osVersion: '14',
  deviceClass: 'mid',
  locale: 'en-US',
  network: 'wifi',
  screenW: 1080,
  screenH: 1920,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  bool sqliteOk() {
    try {
      SqliteStore.open(':memory:', maxBytes: 1024);
      return true;
    } on Object {
      return false;
    }
  }

  if (!sqliteOk()) {
    test('skipped — native libsqlite3 unavailable', () {}, skip: true);
    return;
  }

  testWidgets(
    'first_open is delivered exactly once on a cold start (single owner)',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('sly_first_open');
      addTearDown(() => dir.deleteSync(recursive: true));

      const clock = 1700000000000;
      final delivered = <String>[];
      final store = SqliteStore.open('${dir.path}/fp.db', maxBytes: 10 << 20);
      final gen = UuidV7Generator(random: Random(11), nowMs: () => clock);
      final client = MockClient((request) async {
        final env =
            jsonDecode(utf8.decode(gzip.decode(request.bodyBytes)))
                as Map<String, Object?>;
        final events = (env['events']! as List).cast<Map<String, Object?>>();
        for (final event in events) {
          delivered.add(event['name']! as String);
        }
        return http.Response(
          '{"accepted":${events.length},"quarantined":0}',
          202,
        );
      });

      final engine = Engine(
        telemetry: Telemetry(),
        sessionizer: Sessionizer(
          kv: store.kv,
          uuid: gen,
          timeoutMs: 30 * 60 * 1000,
        ),
        identity: IdentityStore(kv: store.kv, uuid: gen),
        scrubber: const NoopScrubber(),
        queue: store,
        uploader: Uploader(
          client: client,
          queue: store,
          endpoint: Uri.parse('https://fp.example.com'),
          writeKey: 'sly_w_test',
          telemetry: Telemetry(),
          nowMs: () => clock,
          batchSize: 50,
          backoff: Backoff(random: Random(2)),
        ),
        remoteConfig: RemoteConfig(
          client: client,
          endpoint: Uri.parse('https://fp.example.com'),
          writeKey: 'sly_w_test',
          kv: store.kv,
        ),
        uuid: gen,
        ctx: _ctx,
        batchSize: 50,
        nowMs: () => clock,
      );
      final host = InlineEngineHost(engine);
      await host.ready();

      // Binding is live under testWidgets, so the real LifecycleCapture surface
      // installs and emits its cold-start `app_open` into the same pipeline.
      await Sessionly.init(
        SessionlyConfig(
          writeKey: 'sly_w_test',
          endpoint: Uri.parse('https://fp.example.com'),
          autoCapture: const AutoCapture(perf: false),
        ),
        host: host,
        uuid: UuidV7Generator(random: Random(999), nowMs: () => clock),
        nowMs: () => clock,
        spawnWatchdog: false,
        drainInterval: const Duration(days: 1),
      );

      await Sessionly.flush();
      await Sessionly.shutdown();

      expect(
        delivered.where((name) => name == 'app_open'),
        hasLength(1),
        reason: 'sanity: the capture surface ran and reached the engine',
      );
      expect(
        delivered.where((name) => name == 'first_open'),
        hasLength(1),
        reason: 'exactly one owner (engine sessionizer) synthesizes first_open',
      );
    },
  );
}
