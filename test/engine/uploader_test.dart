import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

const _ctx = EventCtx(
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
  final gen = UuidV7Generator(random: Random(3), nowMs: () => 1710000000000);

  String eventJson() => jsonEncode(
    CustomEvent(
      eventId: gen.generate(),
      ts: DateTime.utc(2026, 3, 9),
      sessionId: gen.generate(),
      anonymousId: 'anon_test',
      userId: null,
      screen: null,
      props: const {'k': 'v'},
      ctx: _ctx,
      name: 'demo',
    ).toJson(),
  );

  Future<InMemoryQueueStore> seededQueue(int n) async {
    final q = InMemoryQueueStore(maxBytes: 1 << 20);
    await q.enqueue([for (var i = 0; i < n; i++) eventJson()], nowMs: 1);
    return q;
  }

  Uploader makeUploader(
    http.Client client,
    QueueStore queue,
    Telemetry telemetry, {
    int now = 5000,
    Backoff? backoff,
  }) => Uploader(
    client: client,
    queue: queue,
    endpoint: Uri.parse('https://fp.example.com'),
    writeKey: 'sly_w_secret',
    telemetry: telemetry,
    nowMs: () => now,
    batchSize: 50,
    backoff: backoff,
  );

  group('Uploader response policy', () {
    test(
      '202 acks the batch; gzip body carries a valid protocol envelope',
      () async {
        final queue = await seededQueue(3);
        late http.Request seen;
        final client = MockClient((request) async {
          seen = request;
          return http.Response('{"accepted":3,"quarantined":0}', 202);
        });
        await makeUploader(client, queue, Telemetry()).pumpAll();

        expect(await queue.count(), 0, reason: 'acked after 202');
        expect(seen.url.path, '/v1/events');
        expect(seen.headers['authorization'], 'Bearer sly_w_secret');
        expect(seen.headers['content-encoding'], 'gzip');

        final decoded =
            jsonDecode(utf8.decode(gzip.decode(seen.bodyBytes)))
                as Map<String, Object?>;
        expect(decoded.keys.toSet(), {'protocol', 'sent_at', 'sdk', 'events'});
        expect(decoded['protocol'], 1);
        expect((decoded['sdk']! as Map)['name'], 'sessionly-flutter');
        expect(decoded['events']! as List, hasLength(3));
        // Golden shape: the envelope round-trips through protocol validation.
        expect(() => EventBatch.fromJson(decoded), returnsNormally);
      },
    );

    test('400 drops the poisoned batch and counts a failure', () async {
      final queue = await seededQueue(2);
      final telemetry = Telemetry();
      final client = MockClient((_) async => http.Response('bad', 400));
      await makeUploader(client, queue, telemetry).pumpAll();
      expect(await queue.count(), 0, reason: 'garbage batch dropped');
      expect(telemetry.uploadFailures, greaterThan(0));
    });

    test('401 halts uploads and preserves the queue', () async {
      final queue = await seededQueue(2);
      final client = MockClient((_) async => http.Response('no', 401));
      final uploader = makeUploader(client, queue, Telemetry());
      await uploader.pumpAll();
      expect(uploader.halted, isTrue);
      expect(await queue.count(), 2, reason: 'auth failure never drops data');
    });

    test('401 halt is counted and reported once, never silent', () async {
      // Regression: a bad/rotated write key returns 401. Before the fix the
      // halt set a private flag and incremented nothing, so an operator
      // watching only capture counters saw a healthy SDK while every upload
      // was dead. The halt must be counted (telemetry) and reported (onHalt),
      // exactly once.
      final queue = await seededQueue(4);
      final telemetry = Telemetry();
      var haltSignals = 0;
      final client = MockClient((_) async => http.Response('no', 401));
      final uploader = Uploader(
        client: client,
        queue: queue,
        endpoint: Uri.parse('https://fp.example.com'),
        writeKey: 'sly_w_secret',
        telemetry: telemetry,
        nowMs: () => 5000,
        batchSize: 50,
        onHalt: () => haltSignals++,
      );

      await uploader.pumpAll();
      // A second pump must not re-signal — the transition fires once.
      await uploader.pumpAll();

      expect(uploader.halted, isTrue);
      expect(haltSignals, 1, reason: 'onHalt fires exactly once on transition');
      expect(telemetry.uploadHalts, greaterThan(0), reason: 'halt is counted');
      expect(
        telemetry.hasPending,
        isTrue,
        reason: 'a pending counter forces an sdk_health emission',
      );
      expect(await queue.count(), 4, reason: 'auth failure never drops data');

      // The health event carries the distinct halt counter.
      final props = telemetry.maybeDrain(99999999999);
      expect(props, isNotNull);
      expect(props!['upload_halts'], greaterThan(0));
    });

    test('429 honors Retry-After and keeps the queue', () async {
      final queue = await seededQueue(2);
      final client = MockClient(
        (_) async =>
            http.Response('slow', 429, headers: {'retry-after': '120'}),
      );
      final uploader = makeUploader(client, queue, Telemetry());
      await uploader.pumpAll();
      expect(uploader.nextAttemptMs, 5000 + 120 * 1000);
      expect(await queue.count(), 2);
    });

    test(
      '5xx backs off within the jitter ceiling and keeps the queue',
      () async {
        final queue = await seededQueue(2);
        final telemetry = Telemetry();
        final client = MockClient((_) async => http.Response('boom', 503));
        final uploader = makeUploader(
          client,
          queue,
          telemetry,
          backoff: Backoff(random: Random(1)),
        );
        await uploader.pumpAll();
        final delay = uploader.nextAttemptMs - 5000;
        // Full jitter on the first failure: delay in [0, base(2000)].
        expect(delay, inInclusiveRange(0, 2000));
        expect(await queue.count(), 2);
        expect(telemetry.uploadFailures, 1);
      },
    );

    test('network error backs off and counts a failure', () async {
      final queue = await seededQueue(2);
      final telemetry = Telemetry();
      final client = MockClient((_) async => throw const SocketException('x'));
      final uploader = makeUploader(client, queue, telemetry);
      await uploader.pumpAll();
      expect(telemetry.uploadFailures, 1);
      expect(uploader.nextAttemptMs, greaterThanOrEqualTo(5000));
      expect(await queue.count(), 2);
    });
  });
}
