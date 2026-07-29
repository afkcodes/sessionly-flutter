/// Opt-in HTTP slow-request capture (docs/05). Flutter cannot auto-hook the
/// network stack, so this is an EXPLICIT interceptor: callers either call
/// `recordHttp`/`recordRequest` from their own client, or route requests
/// through the ready-made [SessionlyHttpClient] (a `package:http` BaseClient).
///
/// Only requests slower than the configured threshold emit a `perf/http_slow`
/// event. PII (Rule 7.1): the host is reduced to a bare authority and the path
/// is stripped of any query string / fragment before it can leave the device —
/// query strings routinely carry tokens, emails, and search terms.
library;

import 'package:http/http.dart' as http;
import 'package:sessionly_flutter/src/capture/capture_sink.dart';
import 'package:sessionly_flutter/src/protocol/capture_props.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

/// Records HTTP request timings and emits `perf/http_slow` for slow ones.
class SessionlyHttpTracker {
  /// Wires the tracker to [sink]. [screen]/[thresholdMs] are resolved live so
  /// the current screen and (future remote-tuned) threshold are always fresh.
  SessionlyHttpTracker({
    required CaptureSink sink,
    required String? Function() screen,
    required int Function() thresholdMs,
  }) : _sink = sink,
       _screen = screen,
       _thresholdMs = thresholdMs;

  final CaptureSink _sink;
  final String? Function() _screen;
  final int Function() _thresholdMs;

  /// Records one completed request. Emits `perf/http_slow` only when
  /// [durationMs] exceeds the configured threshold. Never throws.
  ///
  /// [status] is the HTTP status code, or `0` for a network failure (no
  /// response). [host] becomes a bare authority; [path] loses any query or
  /// fragment.
  void recordHttp({
    required String host,
    required String path,
    required String method,
    required int status,
    required int durationMs,
  }) {
    final threshold = _thresholdMs();
    if (durationMs <= threshold) return;
    final cleanPath = _sanitizePath(path);
    if (_isOwnEndpoint(cleanPath)) return; // never measure our own ingest.
    _sink.emit(
      type: EventType.perf,
      name: 'http_slow',
      props: {
        'host': _sanitizeHost(host),
        'path': cleanPath,
        'method': _normalizeMethod(method),
        'status': status < 0
            ? 0
            : (status > httpStatusMax ? httpStatusMax : status),
        'duration_ms': durationMs < 0 ? 0 : durationMs,
        'threshold_ms': threshold,
      },
      screen: _screen(),
    );
  }

  /// Convenience over [recordHttp] that derives host/path from a [url].
  void recordRequest(Uri url, String method, int status, int durationMs) {
    final host = url.hasPort ? '${url.host}:${url.port}' : url.host;
    recordHttp(
      host: host,
      path: url.path.isEmpty ? '/' : url.path,
      method: method,
      status: status,
      durationMs: durationMs,
    );
  }

  static String _sanitizeHost(String host) =>
      host.split('@').last.split('/').first;

  static String _sanitizePath(String path) {
    final stripped = path.split('?').first.split('#').first;
    if (stripped.isEmpty) return '/';
    return stripped.startsWith('/') ? stripped : '/$stripped';
  }

  static String _normalizeMethod(String method) {
    final upper = method.toUpperCase();
    return httpMethods.contains(upper) ? upper : 'OTHER';
  }

  static bool _isOwnEndpoint(String path) =>
      path.endsWith('/v1/events') || path.endsWith('/v1/config');
}

/// A `package:http` [http.BaseClient] that times every request and reports slow
/// ones to its `tracker`. Wrap your existing client:
///
/// ```dart
/// final client = SessionlyHttpClient(inner: http.Client());
/// await client.get(Uri.parse('https://api.example.com/things'));
/// ```
///
/// It never swallows the app's own network errors — a failed request rethrows
/// after being recorded with `status: 0`.
class SessionlyHttpClient extends http.BaseClient {
  /// Wraps [inner] (a fresh [http.Client] by default), reporting to [tracker].
  SessionlyHttpClient({
    required SessionlyHttpTracker tracker,
    http.Client? inner,
  }) : _tracker = tracker,
       _inner = inner ?? http.Client();

  final http.Client _inner;
  final SessionlyHttpTracker _tracker;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final sw = Stopwatch()..start();
    try {
      final response = await _inner.send(request);
      _record(request, response.statusCode, sw.elapsedMilliseconds);
      return response;
    } on Object {
      _record(request, 0, sw.elapsedMilliseconds); // network failure.
      rethrow;
    }
  }

  void _record(http.BaseRequest request, int status, int durationMs) {
    try {
      _tracker.recordRequest(request.url, request.method, status, durationMs);
    } on Object {
      // Recording must never disturb the request (Rule 0.3).
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
