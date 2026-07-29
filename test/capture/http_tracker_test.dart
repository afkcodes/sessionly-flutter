import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

import 'support.dart';

SessionlyHttpTracker buildTracker(RecordingSink sink, {int threshold = 3000}) =>
    SessionlyHttpTracker(
      sink: sink,
      screen: () => 'CheckoutPage',
      thresholdMs: () => threshold,
    );

void main() {
  late RecordingSink sink;

  setUp(() => sink = RecordingSink());

  group('recordHttp threshold', () {
    test('a request under the threshold emits nothing', () {
      buildTracker(sink).recordHttp(
        host: 'api.example.com',
        path: '/v1/pay',
        method: 'POST',
        status: 200,
        durationMs: 500,
      );
      expect(sink.events, isEmpty);
    });

    test('a slow request emits perf/http_slow with the threshold', () {
      buildTracker(sink).recordHttp(
        host: 'api.example.com',
        path: '/v1/pay',
        method: 'POST',
        status: 200,
        durationMs: 4200,
      );
      final e = sink.named('http_slow').single;
      expect(e.type, EventType.perf);
      expect(e.props['host'], 'api.example.com');
      expect(e.props['path'], '/v1/pay');
      expect(e.props['method'], 'POST');
      expect(e.props['status'], 200);
      expect(e.props['duration_ms'], 4200);
      expect(e.props['threshold_ms'], 3000);
      expect(e.screen, 'CheckoutPage');
    });
  });

  group('sanitization (PII, Rule 7.1)', () {
    test('strips credentials from host and query/fragment from path', () {
      buildTracker(sink).recordHttp(
        host: 'user:secret@api.example.com',
        path: '/search?email=user@example.com#frag',
        method: 'get',
        status: 200,
        durationMs: 5000,
      );
      final props = sink.named('http_slow').single.props;
      expect(props['host'], 'api.example.com');
      expect(props['path'], '/search');
      expect(props['method'], 'GET'); // upper-cased
    });

    test('an unknown method maps to OTHER and status clamps to range', () {
      buildTracker(sink).recordHttp(
        host: 'api.example.com',
        path: '/x',
        method: 'PURGE',
        status: 999,
        durationMs: 5000,
      );
      final props = sink.named('http_slow').single.props;
      expect(props['method'], 'OTHER');
      expect(props['status'], 599);
    });

    test('the SDK never measures its own ingest endpoints', () {
      buildTracker(sink)
        ..recordHttp(
          host: 'fp.example.com',
          path: '/v1/events',
          method: 'POST',
          status: 200,
          durationMs: 9000,
        )
        ..recordHttp(
          host: 'fp.example.com',
          path: '/v1/config',
          method: 'GET',
          status: 200,
          durationMs: 9000,
        );
      expect(sink.events, isEmpty);
    });

    test('recordRequest derives host (with port) and path from a Uri', () {
      buildTracker(sink).recordRequest(
        Uri.parse('https://api.example.com:8443/v1/pay?token=abc'),
        'POST',
        200,
        5000,
      );
      final props = sink.named('http_slow').single.props;
      expect(props['host'], 'api.example.com:8443');
      expect(props['path'], '/v1/pay');
    });
  });

  group('SessionlyHttpClient wrapper', () {
    test('records a slow request and returns the response unchanged', () async {
      final inner = MockClient((_) async => http.Response('ok', 200));
      final client = SessionlyHttpClient(
        tracker: buildTracker(sink, threshold: 0),
        inner: inner,
      );
      final resp = await client.get(
        Uri.parse('https://api.example.com/things'),
      );
      expect(resp.statusCode, 200);
      expect(utf8.decode(resp.bodyBytes), 'ok');
      final e = sink.named('http_slow').single;
      expect(e.props['host'], 'api.example.com');
      expect(e.props['path'], '/things');
      expect(e.props['method'], 'GET');
      client.close();
    });

    test('records status 0 on a network failure and rethrows', () async {
      final inner = MockClient((_) async => throw const _NetworkDown());
      final client = SessionlyHttpClient(
        tracker: buildTracker(sink, threshold: 0),
        inner: inner,
      );
      await expectLater(
        client.get(Uri.parse('https://api.example.com/things')),
        throwsA(isA<_NetworkDown>()),
      );
      expect(sink.named('http_slow').single.props['status'], 0);
      client.close();
    });
  });
}

class _NetworkDown implements Exception {
  const _NetworkDown();
}
