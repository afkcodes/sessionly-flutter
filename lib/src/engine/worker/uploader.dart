/// The uploader (docs/05 invariant 4). Reads batches from the disk queue, gzips
/// the protocol envelope, POSTs it, and applies the exact response policy from
/// the wire target. Failures back off with jitter; while backing off, capture
/// keeps flowing to disk within caps (Rule 0.7 — fail open, no retry storms).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sessionly_flutter/src/engine/telemetry.dart';
import 'package:sessionly_flutter/src/engine/worker/backoff.dart';
import 'package:sessionly_flutter/src/engine/worker/queue_store.dart';
import 'package:sessionly_flutter/src/protocol/envelope.dart';
import 'package:sessionly_flutter/src/protocol/formats.dart';

/// SDK semver reported in every batch's `sdk.version`.
const String sessionlySdkVersion = '0.1.0-dev';

/// Batches serialized events off the disk queue and uploads them.
class Uploader {
  /// Creates an uploader.
  Uploader({
    required http.Client client,
    required QueueStore queue,
    required Uri endpoint,
    required String writeKey,
    required Telemetry telemetry,
    required int Function() nowMs,
    required int batchSize,
    Backoff? backoff,
    Duration flushInterval = const Duration(seconds: 30),
    void Function()? onHalt,
  }) : _client = client,
       _queue = queue,
       _endpoint = endpoint,
       _writeKey = writeKey,
       _telemetry = telemetry,
       _nowMs = nowMs,
       _batchSize = batchSize,
       _backoff = backoff ?? Backoff(),
       _flushInterval = flushInterval,
       _onHalt = onHalt;

  final http.Client _client;
  final QueueStore _queue;
  final Uri _endpoint;
  final String _writeKey;
  final Telemetry _telemetry;
  final int Function() _nowMs;
  final int _batchSize;
  final Backoff _backoff;
  final Duration _flushInterval;
  final void Function()? _onHalt;

  Timer? _timer;
  bool _halted = false;
  int _nextAttemptMs = 0;
  bool _inFlight = false;

  /// `true` after a 401 — a config problem, uploads stop until reconfigured.
  bool get halted => _halted;

  /// Earliest ms at which the next attempt may run (backoff gate).
  int get nextAttemptMs => _nextAttemptMs;

  /// Starts the periodic flush timer.
  void start() {
    _timer ??= Timer.periodic(_flushInterval, (_) => unawaited(pumpAll()));
  }

  /// Stops the periodic flush timer.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Drains the queue until it is empty or an attempt is blocked — by backoff,
  /// halt, or a non-acking response.
  Future<void> pumpAll() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      while (await _pumpOnce()) {}
    } finally {
      _inFlight = false;
    }
  }

  Future<bool> _pumpOnce() async {
    if (_halted) return false;
    final now = _nowMs();
    if (now < _nextAttemptMs) return false;
    final rows = await _queue.peek(_batchSize);
    if (rows.isEmpty) return false;
    final ids = rows.map((r) => r.id).toList(growable: false);
    final body = _envelope(rows, now);
    try {
      final resp = await _send(body);
      return _handle(resp, ids, now);
    } on Object {
      _telemetry.uploadFailures++;
      _nextAttemptMs = now + _backoff.nextDelayMs();
      return false;
    }
  }

  Future<bool> _handle(http.Response resp, List<int> ids, int now) async {
    switch (resp.statusCode) {
      case 202:
        await _queue.ack(ids);
        _backoff.reset();
        _nextAttemptMs = 0;
        return true;
      case 400:
        // Batch is garbage; it will never succeed — drop it (Rule 0.7).
        await _queue.ack(ids);
        _telemetry.uploadFailures++;
        _backoff.reset();
        return true;
      case 401:
        // Auth/config problem (e.g. an invalid or rotated write key) — this is
        // terminal: stop uploading, do not drop. Count and report it (Rule 0.3)
        // so a halt is never silent — every other failure branch counts, and a
        // silent halt here is indistinguishable from a dead engine to an
        // operator watching only capture counters. Fire [_onHalt] once so the
        // main isolate can surface it (Sessionly.debugStats).
        _telemetry.uploadHalts++;
        if (!_halted) {
          _halted = true;
          _onHalt?.call();
        }
        return false;
      case 429:
        _telemetry.uploadFailures++;
        final retry = _retryAfterMs(resp);
        _nextAttemptMs = now + (retry ?? _backoff.nextDelayMs());
        return false;
      default:
        _telemetry.uploadFailures++;
        _nextAttemptMs = now + _backoff.nextDelayMs();
        return false;
    }
  }

  int? _retryAfterMs(http.Response resp) {
    final header = resp.headers['retry-after'];
    if (header == null) return null;
    final seconds = int.tryParse(header.trim());
    return seconds == null ? null : seconds * 1000;
  }

  Map<String, Object?> _envelope(List<QueueRow> rows, int now) => {
    'protocol': protocolVersion,
    'sent_at': formatIsoDateTimeMs(
      DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
    ),
    'sdk': {'name': flutterSdkName, 'version': sessionlySdkVersion},
    'events': rows
        .map((r) => jsonDecode(r.json) as Map<String, Object?>)
        .toList(growable: false),
  };

  Future<http.Response> _send(Map<String, Object?> envelope) {
    final gzipped = gzip.encode(utf8.encode(jsonEncode(envelope)));
    return _client.post(
      _eventsUri(),
      headers: {
        'authorization': 'Bearer $_writeKey',
        'content-type': 'application/json',
        'content-encoding': 'gzip',
      },
      body: gzipped,
    );
  }

  Uri _eventsUri() {
    final base = _endpoint.path.endsWith('/')
        ? _endpoint.path.substring(0, _endpoint.path.length - 1)
        : _endpoint.path;
    return _endpoint.replace(path: '$base/v1/events');
  }
}
