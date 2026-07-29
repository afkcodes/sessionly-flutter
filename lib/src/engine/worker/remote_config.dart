/// Remote config + kill switch (docs/05 invariants 6 & 8). Fetched lazily from
/// `GET {endpoint}/v1/config`, cached in kv, and refreshed every 6 h. Any fetch
/// failure (including a 404 today) falls back to cache/defaults and never blocks
/// startup. `enabled:false` disables capture entirely.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sessionly_flutter/src/engine/worker/kv_store.dart';

/// The minimal remote config schema.
class RemoteConfigValues {
  /// Creates a config value set.
  const RemoteConfigValues({
    required this.enabled,
    required this.sampleRate,
    required this.flushIntervalS,
    required this.flushBatchSize,
    this.flags = const {},
    this.experiments = const {},
  });

  /// Parses from a decoded config map, defaulting missing/invalid fields.
  factory RemoteConfigValues.fromJson(Map<String, Object?> json) {
    final rate = json['sample_rate'];
    return RemoteConfigValues(
      enabled: (json['enabled'] as bool?) ?? true,
      sampleRate: rate is num ? rate.toDouble().clamp(0.0, 1.0) : 1.0,
      flushIntervalS: json['flush_interval_s'] is int
          ? json['flush_interval_s']! as int
          : 30,
      flushBatchSize: json['flush_batch_size'] is int
          ? json['flush_batch_size']! as int
          : 50,
      flags: _parseFlags(json['flags']),
      experiments: _parseExperiments(json['experiments']),
    );
  }

  /// Engine-wide defaults used until the first successful fetch.
  static const RemoteConfigValues defaults = RemoteConfigValues(
    enabled: true,
    sampleRate: 1,
    flushIntervalS: 30,
    flushBatchSize: 50,
  );

  /// Defensively parse the delivered flag map (docs/06 § in-app flag channel):
  /// each entry must carry a boolean `enabled`; a malformed entry is skipped so
  /// one bad flag never corrupts the map (fail-safe, default-off). The result
  /// is a primitive map (`key -> {enabled, value}`), so it crosses the isolate
  /// boundary unchanged.
  static Map<String, Object?> _parseFlags(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, Object?>{};
    raw.forEach((key, entry) {
      if (key is String && entry is Map && entry['enabled'] is bool) {
        out[key] = <String, Object?>{
          'enabled': entry['enabled'],
          if (entry.containsKey('value')) 'value': entry['value'],
        };
      }
    });
    return out;
  }

  /// Defensively parse the delivered running-experiment map (docs/10 Suite
  /// modules): each entry must carry a non-empty `variants` list of
  /// `{name, weight, value?}` maps; malformed entries/variants are skipped so one
  /// bad experiment never corrupts the map (fail-safe — the SDK then assigns
  /// nothing). The result is a primitive map so it crosses the isolate
  /// boundary.
  static Map<String, Object?> _parseExperiments(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, Object?>{};
    raw.forEach((key, entry) {
      if (key is! String || entry is! Map) return;
      final rawVariants = entry['variants'];
      if (rawVariants is! List) return;
      final variants = <Object?>[];
      for (final v in rawVariants) {
        if (v is! Map) continue;
        final name = v['name'];
        final weight = v['weight'];
        if (name is! String || name.isEmpty || weight is! num || weight <= 0) {
          continue;
        }
        variants.add(<String, Object?>{
          'name': name,
          'weight': weight,
          if (v.containsKey('value')) 'value': v['value'],
        });
      }
      if (variants.isEmpty) return;
      out[key] = <String, Object?>{
        'flagKey': entry['flagKey'] is String ? entry['flagKey'] : '',
        'variants': variants,
      };
    });
    return out;
  }

  /// Master kill switch — `false` makes capture a no-op.
  final bool enabled;

  /// Fraction of events to keep, `0.0`..`1.0`.
  final double sampleRate;

  /// Flush cadence in seconds.
  final int flushIntervalS;

  /// Flush threshold in events.
  final int flushBatchSize;

  /// The delivered feature-flag map (docs/06 § in-app flag channel): `key ->
  /// {enabled, value}`, primitives only (crosses the isolate boundary as-is).
  /// Empty until the first successful fetch. Read by `Sessionly.flag()`.
  final Map<String, Object?> flags;

  /// The delivered running-experiment map (docs/10 Suite modules): `key ->
  /// {flagKey, variants:[{name, weight, value?}]}`, primitives only. Empty
  /// until the first successful fetch. Read (with the actor seed) by
  /// `Sessionly.experiment()`.
  final Map<String, Object?> experiments;

  /// The wire/cache map form.
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'sample_rate': sampleRate,
    'flush_interval_s': flushIntervalS,
    'flush_batch_size': flushBatchSize,
    'flags': flags,
    'experiments': experiments,
  };
}

/// Fetches, caches, and exposes the current [RemoteConfigValues].
class RemoteConfig {
  /// Creates a remote-config client. [endpoint] is the ingest base Uri.
  /// [onFlags], when given, is called with the delivered flag map on every
  /// fetch/cache load — the isolate host relays it to the main isolate so
  /// `Sessionly.flag()` can read it synchronously (docs/06 § in-app flag channel).
  RemoteConfig({
    required http.Client client,
    required Uri endpoint,
    required String writeKey,
    required KvStore kv,
    Duration refreshInterval = const Duration(hours: 6),
    void Function(Map<String, Object?> flags)? onFlags,
    void Function(Map<String, Object?> experiments)? onExperiments,
  }) : _client = client,
       _endpoint = endpoint,
       _writeKey = writeKey,
       _kv = kv,
       _refreshInterval = refreshInterval,
       _onFlags = onFlags,
       _onExperiments = onExperiments;

  final http.Client _client;
  final Uri _endpoint;
  final String _writeKey;
  final KvStore _kv;
  final Duration _refreshInterval;
  final void Function(Map<String, Object?> flags)? _onFlags;
  final void Function(Map<String, Object?> experiments)? _onExperiments;

  RemoteConfigValues _values = RemoteConfigValues.defaults;
  Timer? _timer;

  /// Current config (defaults until the first fetch/cache hit).
  RemoteConfigValues get values => _values;

  /// `false` when the kill switch is engaged.
  bool get enabled => _values.enabled;

  /// Loads any cached config, then kicks off a non-blocking refresh and starts
  /// the periodic refresh timer.
  Future<void> start() async {
    final cached = await _kv.get(KvKey.remoteConfig);
    if (cached != null) {
      _values = _parse(cached) ?? _values;
      _onFlags?.call(_values.flags);
      _onExperiments?.call(_values.experiments);
    }
    unawaited(refresh());
    _timer ??= Timer.periodic(_refreshInterval, (_) => unawaited(refresh()));
  }

  /// Fetches config once. Any failure is swallowed — cache/defaults stand.
  Future<void> refresh() async {
    try {
      final resp = await _client.get(
        _configUri(),
        headers: {'authorization': 'Bearer $_writeKey'},
      );
      if (resp.statusCode != 200) return;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) return;
      _values = RemoteConfigValues.fromJson(decoded.cast<String, Object?>());
      await _kv.set(KvKey.remoteConfig, jsonEncode(_values.toJson()));
      _onFlags?.call(_values.flags);
      _onExperiments?.call(_values.experiments);
    } on Object {
      // Fail open (Rule 0.7): keep cache/defaults.
    }
  }

  /// Stops the refresh timer.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  RemoteConfigValues? _parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return RemoteConfigValues.fromJson(decoded.cast<String, Object?>());
      }
    } on Object {
      // Ignore corrupt cache.
    }
    return null;
  }

  Uri _configUri() {
    final base = _endpoint.path.endsWith('/')
        ? _endpoint.path.substring(0, _endpoint.path.length - 1)
        : _endpoint.path;
    return _endpoint.replace(path: '$base/v1/config');
  }
}
