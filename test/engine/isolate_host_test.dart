import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

/// A real loopback ingest server: accepts gzipped `POST /v1/events`, validates
/// each batch through the protocol parser, records events, and 202s. Runs
/// entirely host-side so nothing fake ever crosses the isolate port.
class LoopbackIngest {
  LoopbackIngest._(
    this._server, {
    required this.eventsStatus,
    required this.flags,
    required this.experiments,
  });

  /// Starts a loopback ingest. [eventsStatus] overrides the `POST /v1/events`
  /// response code (202 by default; 401 exercises the auth-halt path). [flags]
  /// is the feature-flag map served at `GET /v1/config` (empty by default);
  /// [experiments] is the running-experiment map served alongside it.
  static Future<LoopbackIngest> start({
    int eventsStatus = 202,
    Map<String, Object?> flags = const {},
    Map<String, Object?> experiments = const {},
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final ingest = LoopbackIngest._(
      server,
      eventsStatus: eventsStatus,
      flags: flags,
      experiments: experiments,
    );
    unawaited(ingest._serve());
    return ingest;
  }

  final HttpServer _server;

  /// Status code returned for every `POST /v1/events`.
  final int eventsStatus;

  /// The feature-flag map served at `GET /v1/config`.
  final Map<String, Object?> flags;

  /// The running-experiment map served at `GET /v1/config`.
  final Map<String, Object?> experiments;

  /// Every event received, in arrival order.
  final List<SessionlyEvent> events = [];

  /// Size of each accepted batch.
  final List<int> batchSizes = [];

  /// Count of `GET /v1/config` requests served (the flag-delivery poll).
  int configRequests = 0;

  int get port => _server.port;

  Uri get endpoint => Uri.parse('http://127.0.0.1:$port');

  Future<void> _serve() async {
    await for (final request in _server) {
      if (request.method == 'POST' && request.uri.path == '/v1/events') {
        await _handleEvents(request);
      } else if (request.method == 'GET' && request.uri.path == '/v1/config') {
        // Remote config + feature-flag delivery (docs/06 § in-app flag channel).
        configRequests++;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'enabled': true,
              'flags': flags,
              'experiments': experiments,
            }),
          );
        await request.response.close();
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    }
  }

  Future<void> _handleEvents(HttpRequest request) async {
    final gzipped = await _collect(request);
    final json = utf8.decode(gzip.decode(gzipped));
    // Strict protocol validation of the real wire payload.
    final batch = EventBatch.fromJson(jsonDecode(json) as Map<String, Object?>);
    batchSizes.add(batch.events.length);
    events.addAll(batch.events);
    if (eventsStatus == HttpStatus.accepted) {
      request.response
        ..statusCode = HttpStatus.accepted
        ..headers.contentType = ContentType.json
        ..write('{"accepted":${batch.events.length},"quarantined":0}');
    } else {
      request.response
        ..statusCode = eventsStatus
        ..write('{"error":"unauthorized"}');
    }
    await request.response.close();
  }

  Future<List<int>> _collect(HttpRequest request) =>
      request.expand((chunk) => chunk).toList();

  Future<void> close() => _server.close(force: true);
}

/// Fake platform: a temp storage dir + a fixed context snapshot. Keeps
/// `path_provider`/`package_info_plus` out of the test while the engine still
/// runs the real isolate/sqlite/HTTP path.
class FakePlatform implements SessionlyPlatform {
  FakePlatform(this._dir);

  final String _dir;

  @override
  Future<String> storageDirectory() async => _dir;

  @override
  Future<CtxSnapshot> snapshot() async => const CtxSnapshot(
    appVersion: '1.0.0',
    build: '42',
    os: 'android',
    osVersion: '14',
    deviceClass: 'mid',
    locale: 'en-US',
    network: 'wifi',
    screenW: 1080,
    screenH: 1920,
  );
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

  group('IsolateEngineHost (real production path)', () {
    if (!sqliteOk()) {
      test('skipped — native libsqlite3 unavailable', () {}, skip: true);
      return;
    }

    late Directory dir;
    late LoopbackIngest ingest;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('sly_isolate');
      ingest = await LoopbackIngest.start();
    });

    tearDown(() async {
      await ingest.close();
      dir.deleteSync(recursive: true);
    });

    SessionlyConfig config() => SessionlyConfig(
      writeKey: 'sly_w_isolate',
      endpoint: ingest.endpoint,
      flushIntervalSeconds: 1,
    );

    Set<String> demoIds() => ingest.events
        .where((e) => e.name == 'demo_event')
        .map((e) => e.eventId)
        .toSet();

    test(
      'spawns a real isolate, delivers events, and shuts down cleanly',
      () async {
        // Real Isolate.spawn + real sqlite (temp dir) + real HTTP to loopback.
        await Sessionly.init(config(), platform: FakePlatform(dir.path));

        for (var i = 0; i < 60; i++) {
          Sessionly.track('demo_event', props: {'i': i});
        }
        await Sessionly.flush();

        final ids = demoIds();
        expect(ids, hasLength(60), reason: 'all 60 delivered, ids unique');
        expect(ingest.batchSizes, isNotEmpty);
        expect(
          ingest.batchSizes.every((n) => n <= 50),
          isTrue,
          reason: 'batches never exceed the flush size',
        );
        // Lifecycle events were synthesized on the real path too.
        expect(ingest.events.any((e) => e.name == 'session_start'), isTrue);

        // Graceful shutdown: must return (isolate exits) without hanging.
        await Sessionly.shutdown().timeout(const Duration(seconds: 10));
      },
    );

    test('re-init after shutdown works (fresh isolate)', () async {
      await Sessionly.init(config(), platform: FakePlatform(dir.path));
      Sessionly.track('demo_event', props: const {'round': 1});
      await Sessionly.flush();
      await Sessionly.shutdown().timeout(const Duration(seconds: 10));
      final afterFirst = demoIds().length;
      expect(afterFirst, 1);

      // Second full lifecycle on a brand-new isolate.
      await Sessionly.init(config(), platform: FakePlatform(dir.path));
      Sessionly.track('demo_event', props: const {'round': 2});
      await Sessionly.flush();
      await Sessionly.shutdown().timeout(const Duration(seconds: 10));

      expect(demoIds().length, 2, reason: 're-init delivers again, ids unique');
    });
  });

  group('IsolateEngineHost flag delivery (real production path)', () {
    if (!sqliteOk()) {
      test('skipped — native libsqlite3 unavailable', () {}, skip: true);
      return;
    }

    late Directory dir;
    late LoopbackIngest ingest;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('sly_flags');
      // Serve a live flag map from the real /v1/config endpoint.
      ingest = await LoopbackIngest.start(
        flags: {
          'new_checkout': {'enabled': true, 'value': 'variant_b'},
          'beta_banner': {'enabled': false},
        },
      );
    });

    tearDown(() async {
      // Tear the singleton down so the next group's init is not a no-op.
      await Sessionly.shutdown().timeout(const Duration(seconds: 10));
      await ingest.close();
      dir.deleteSync(recursive: true);
    });

    SessionlyConfig config() => SessionlyConfig(
      writeKey: 'sly_w_flags',
      endpoint: ingest.endpoint,
      flushIntervalSeconds: 1,
    );

    test(
      'delivers the flag map to the main isolate; flag() reads it and emits '
      'a single flag_exposure',
      () async {
        await Sessionly.init(config(), platform: FakePlatform(dir.path));

        // Wait for the config fetch to land AND the reverse channel to relay
        // the flag map to the main isolate, without calling flag() (which would
        // emit an exposure before delivery). Poll the served config request,
        // then a short grace for the status-port hop.
        final deadline = DateTime.now().add(const Duration(seconds: 8));
        while (ingest.configRequests == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));

        // Synchronous, O(1) reads of the delivered map.
        final flag = Sessionly.flag('new_checkout');
        expect(flag.enabled, isTrue, reason: 'delivered enabled state');
        expect(flag.value, 'variant_b', reason: 'delivered structured value');
        expect(Sessionly.isEnabled('beta_banner'), isFalse);
        expect(Sessionly.isEnabled('absent'), isFalse, reason: 'default-off');

        // Reading again does not double-emit (dedup per key per run).
        Sessionly.flag('new_checkout');
        await Sessionly.flush();

        final exposures = ingest.events
            .where((e) => e.name == 'flag_exposure')
            .toList();
        final checkout = exposures
            .where((e) => e.props['key'] == 'new_checkout')
            .toList();
        expect(checkout, hasLength(1), reason: 'exactly one exposure per key');
        expect(checkout.first.props['enabled'], isTrue);
        expect(checkout.first.props['value'], 'variant_b');
      },
    );
  });

  group('IsolateEngineHost experiment delivery (real production path)', () {
    if (!sqliteOk()) {
      test('skipped — native libsqlite3 unavailable', () {}, skip: true);
      return;
    }

    late Directory dir;
    late LoopbackIngest ingest;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('sly_experiments');
      // Serve a live running-experiment map from the real /v1/config endpoint.
      ingest = await LoopbackIngest.start(
        experiments: {
          'checkout_button_color': {
            'flagKey': 'checkout_button_color',
            'variants': [
              {'name': 'control', 'weight': 1},
              {
                'name': 'treatment',
                'weight': 1,
                'value': {'color': 'green'},
              },
            ],
          },
        },
      );
    });

    tearDown(() async {
      await Sessionly.shutdown().timeout(const Duration(seconds: 10));
      await ingest.close();
      dir.deleteSync(recursive: true);
    });

    SessionlyConfig config() => SessionlyConfig(
      writeKey: 'sly_w_experiments',
      endpoint: ingest.endpoint,
      flushIntervalSeconds: 1,
    );

    test(
      'delivers experiments + seed to the main isolate; experiment() assigns '
      'deterministically and emits a single experiment_exposure',
      () async {
        await Sessionly.init(config(), platform: FakePlatform(dir.path));

        // Wait for the config fetch to land AND the reverse channel to relay
        // both the experiment map and the actor seed to the main isolate.
        final deadline = DateTime.now().add(const Duration(seconds: 8));
        while (ingest.configRequests == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));

        // Synchronous, O(1) assignment of the delivered experiment.
        final first = Sessionly.experiment('checkout_button_color');
        expect(first.isAssigned, isTrue, reason: 'a variant is assigned');
        expect(
          ['control', 'treatment'].contains(first.variant),
          isTrue,
          reason: 'assigned to one of the delivered variants',
        );

        // Sticky per actor: a second read resolves to the SAME variant.
        final second = Sessionly.experiment('checkout_button_color');
        expect(second.variant, first.variant, reason: 'sticky per actor');

        // An absent experiment is unassigned and never throws.
        expect(Sessionly.experiment('absent').isAssigned, isFalse);

        await Sessionly.flush();

        final exposures = ingest.events
            .where((e) => e.name == 'experiment_exposure')
            .where((e) => e.props['key'] == 'checkout_button_color')
            .toList();
        expect(exposures, hasLength(1), reason: 'exactly one exposure per key');
        expect(exposures.first.props['variant'], first.variant);
      },
    );
  });

  group('IsolateEngineHost auth-halt (real production path)', () {
    if (!sqliteOk()) {
      test('skipped — native libsqlite3 unavailable', () {}, skip: true);
      return;
    }

    late Directory dir;
    late LoopbackIngest ingest;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('sly_isolate_401');
      // Every POST /v1/events answers 401 — a bad/rotated write key.
      ingest = await LoopbackIngest.start(eventsStatus: 401);
    });

    tearDown(() async {
      await Sessionly.shutdown().timeout(const Duration(seconds: 10));
      await ingest.close();
      dir.deleteSync(recursive: true);
    });

    test(
      'a 401 surfaces as upload_halted in debugStats — never silent (Rule 0.3)',
      () async {
        // The exact on-device failure that read as an "isolate hang": the SDK
        // captures happily, the real isolate/sqlite/http path all run, but every
        // upload 401s and halts. Before the fix debugStats showed a healthy SDK
        // (upload_halted absent); this asserts the halt is observable off the
        // engine isolate through the real Isolate.spawn + status-port channel.
        await Sessionly.init(
          SessionlyConfig(
            writeKey: 'sly_w_wrong',
            endpoint: ingest.endpoint,
            flushIntervalSeconds: 1,
          ),
          platform: FakePlatform(dir.path),
        );

        Sessionly.track('demo_event', props: const {'i': 0});
        // Force an upload attempt; the worker will 401 and halt.
        await Sessionly.flush();
        // Let the worker's status-port message reach the host listener.
        for (var i = 0; i < 20; i++) {
          if (Sessionly.debugStats()['upload_halted'] == 1) break;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }

        final stats = Sessionly.debugStats();
        expect(
          stats['upload_halted'],
          1,
          reason: 'the 401 halt must be visible to the host',
        );
        expect(
          stats['captured'],
          greaterThan(0),
          reason: 'capture keeps flowing — the SDK is not dead, just halted',
        );
      },
    );
  });
}
