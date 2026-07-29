import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

const _ctx = CtxSnapshot(
  appVersion: '1.0.0',
  build: null,
  os: 'android',
  osVersion: '14',
  deviceClass: 'mid',
  locale: 'en-US',
  network: 'wifi',
  screenW: 1080,
  screenH: 1920,
);

void main() {
  test('remote config enabled:false drops all capture (kill switch)', () async {
    final kv = InMemoryKvStore();
    // Cached kill switch present at startup.
    await kv.set(KvKey.remoteConfig, jsonEncode({'enabled': false}));
    final queue = InMemoryQueueStore(maxBytes: 1 << 20);
    var now = 1000;
    final gen = UuidV7Generator(random: Random(5), nowMs: () => now);
    // Config endpoint 404s today — the cached kill switch must stand.
    final client = MockClient((_) async => http.Response('', 404));

    final engine = Engine(
      telemetry: Telemetry(),
      sessionizer: Sessionizer(kv: kv, uuid: gen, timeoutMs: 1800000),
      identity: IdentityStore(kv: kv, uuid: gen),
      scrubber: const NoopScrubber(),
      queue: queue,
      uploader: Uploader(
        client: client,
        queue: queue,
        endpoint: Uri.parse('https://fp.example.com'),
        writeKey: 'wk',
        telemetry: Telemetry(),
        nowMs: () => now,
        batchSize: 50,
      ),
      remoteConfig: RemoteConfig(
        client: client,
        endpoint: Uri.parse('https://fp.example.com'),
        writeKey: 'wk',
        kv: kv,
      ),
      uuid: gen,
      ctx: _ctx,
      batchSize: 50,
      nowMs: () => now,
    );
    await engine.start();

    now = 2000;
    await engine.submit([
      {
        RecordKey.kind: RecordKind.event,
        RecordKey.eventId: gen.generate(),
        RecordKey.tsMs: now,
        RecordKey.type: 'custom',
        RecordKey.name: 'demo',
        RecordKey.props: <String, Object?>{},
        RecordKey.screen: null,
      },
    ]);

    expect(await queue.count(), 0, reason: 'kill switch drops all capture');
    await engine.shutdown();
  });
}
