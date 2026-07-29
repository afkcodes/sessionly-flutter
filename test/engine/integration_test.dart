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

/// A fake ingest server: dedups by `event_id`, records batch sizes, and can be
/// flipped offline. Mirrors the "delivered exactly once" contract.
class FakeIngest {
  final Set<String> demoDelivered = {};
  final List<int> batchSizes = [];
  bool online = true;

  http.Client client() => MockClient((request) async {
    if (request.method != 'POST' || !request.url.path.endsWith('/v1/events')) {
      return http.Response('', 404);
    }
    if (!online) throw const SocketException('offline');
    final env =
        jsonDecode(utf8.decode(gzip.decode(request.bodyBytes)))
            as Map<String, Object?>;
    final events = (env['events']! as List).cast<Map<String, Object?>>();
    batchSizes.add(events.length);
    for (final event in events) {
      if (event['name'] == 'demo_event') {
        demoDelivered.add(event['event_id']! as String);
      }
    }
    return http.Response(
      '{"accepted":${events.length},"quarantined":0}',
      202,
    );
  });
}

void main() {
  bool sqliteOk() {
    try {
      SqliteStore.open(':memory:', maxBytes: 1024);
      return true;
    } on Object {
      return false;
    }
  }

  group('Full engine integration (Dart-only)', () {
    if (!sqliteOk()) {
      test('skipped — native libsqlite3 unavailable', () {}, skip: true);
      return;
    }

    late Directory dir;
    late int clock;
    late SqliteStore store;
    late FakeIngest ingest;
    late InlineEngineHost host;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('sly_integration');
      clock = 1700000000000;
      ingest = FakeIngest();
      store = SqliteStore.open('${dir.path}/fp.db', maxBytes: 10 << 20);
      final engineGen = UuidV7Generator(random: Random(11), nowMs: () => clock);
      final client = ingest.client();
      final engine = Engine(
        telemetry: Telemetry(),
        sessionizer: Sessionizer(
          kv: store.kv,
          uuid: engineGen,
          timeoutMs: 30 * 60 * 1000,
        ),
        identity: IdentityStore(kv: store.kv, uuid: engineGen),
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
        uuid: engineGen,
        ctx: _ctx,
        batchSize: 50,
        nowMs: () => clock,
      );
      host = InlineEngineHost(engine);
      await host.ready();
      await Sessionly.init(
        SessionlyConfig(
          writeKey: 'sly_w_test',
          endpoint: Uri.parse('https://fp.example.com'),
        ),
        host: host,
        uuid: UuidV7Generator(random: Random(999), nowMs: () => clock),
        nowMs: () => clock,
        drainInterval: const Duration(days: 1),
      );
    });

    tearDown(() async {
      await Sessionly.shutdown();
      dir.deleteSync(recursive: true);
    });

    test(
      'delivers 120 events in batches of <= 50, then drains the disk',
      () async {
        for (var i = 0; i < 120; i++) {
          Sessionly.track('demo_event', props: {'i': i});
        }
        await Sessionly.flush();

        expect(ingest.demoDelivered, hasLength(120));
        expect(ingest.batchSizes, isNotEmpty);
        expect(ingest.batchSizes.every((n) => n <= 50), isTrue);
        expect(await store.count(), 0, reason: 'disk empty after acks');
      },
    );

    test(
      'offline events persist and are delivered exactly once on recovery',
      () async {
        // Phase 1 — online.
        for (var i = 0; i < 120; i++) {
          Sessionly.track('demo_event', props: {'i': i});
        }
        await Sessionly.flush();
        expect(ingest.demoDelivered, hasLength(120));

        // Phase 2 — offline: capture keeps flowing to disk within caps.
        ingest.online = false;
        for (var i = 120; i < 240; i++) {
          Sessionly.track('demo_event', props: {'i': i});
        }
        await Sessionly.flush();
        expect(await store.count(), greaterThan(0), reason: 'buffered offline');
        expect(ingest.demoDelivered, hasLength(120));

        // Phase 3 — recover: advance past backoff, everything drains once.
        ingest.online = true;
        clock += 10 * 60 * 1000;
        await Sessionly.flush();

        expect(ingest.demoDelivered, hasLength(240), reason: 'exactly once');
        expect(await store.count(), 0);
        expect(ingest.batchSizes.every((n) => n <= 50), isTrue);
      },
    );
  });
}
