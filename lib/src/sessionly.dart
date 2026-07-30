/// The public facade (docs/05 invariant 1). Every entry point is a thin,
/// no-throw wrapper over the capture gate: validate-cheaply, stamp, enqueue.
/// Nothing here does I/O or serialization — that all lives behind the
/// [EngineHost] on a background isolate.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:sessionly_flutter/src/capture/capture_sink.dart';
import 'package:sessionly_flutter/src/capture/http_tracker.dart';
import 'package:sessionly_flutter/src/capture/runtime.dart';
import 'package:sessionly_flutter/src/config.dart';
import 'package:sessionly_flutter/src/engine/capture_gate.dart';
import 'package:sessionly_flutter/src/engine/engine_host.dart';
import 'package:sessionly_flutter/src/engine/isolate_host.dart';
import 'package:sessionly_flutter/src/engine/ring_buffer.dart';
import 'package:sessionly_flutter/src/experiment_assignment.dart';
import 'package:sessionly_flutter/src/platform/default_platform.dart';
import 'package:sessionly_flutter/src/platform/sessionly_platform.dart';
import 'package:sessionly_flutter/src/protocol/uuid_v7.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

/// Static entry point for the Sessionly SDK.
///
/// ```dart
/// await Sessionly.init(SessionlyConfig(
///   writeKey: 'sly_w_...',
///   endpoint: Uri.parse('https://fp.example.com'),
/// ));
/// Sessionly.track('checkout_completed', props: {'value': 499});
/// ```
abstract final class Sessionly {
  static CaptureGate? _gate;
  static EngineHost? _host;
  static SessionlyConfig? _config;
  static CaptureRuntime? _captureRuntime;
  static SessionlyHttpTracker? _httpTracker;
  static Future<void>? _ready;
  static bool _initialized = false;
  static bool _enabled = false;
  static int _internalErrors = 0;
  // Feature-flag keys already exposed this run (docs/06: `flag_exposure` at most
  // once per session per key; a single SDK run is one session's worth of
  // exposure). Reset on init.
  static final Set<String> _exposedFlags = <String>{};
  // Experiment keys already exposed this run (docs/10: `experiment_exposure` at
  // most once per run per key). Reset on init.
  static final Set<String> _exposedExperiments = <String>{};

  // A tracker that discards everything — returned by [httpTracker] before init
  // or when capture is disabled, so callers can wire it unconditionally.
  static final SessionlyHttpTracker _disabledHttpTracker = SessionlyHttpTracker(
    sink: const _DiscardSink(),
    screen: () => null,
    thresholdMs: () => 3000,
  );

  /// Swallowed-error count (Rule 0.3). Test/debug affordance only.
  static int get debugInternalErrorCount => _internalErrors;

  /// The opt-in HTTP slow-request tracker (docs/05). Flutter cannot auto-hook
  /// the network stack, so instrument requests explicitly — call
  /// [SessionlyHttpTracker.recordRequest] from your client, or route through a
  /// [SessionlyHttpClient]. Only requests slower than
  /// [SessionlyConfig.httpSlowThresholdMs] emit a `perf/http_slow` event.
  /// Returns a no-op tracker before [init] or when capture is disabled.
  static SessionlyHttpTracker get httpTracker =>
      _httpTracker ?? _disabledHttpTracker;

  /// A read-only snapshot of main-isolate SDK counters, for debug overlays and
  /// tests. No I/O, never throws, and nothing here ever reaches the wire.
  /// Values are best-effort main-isolate views (upload/ack counts live on the
  /// engine isolate and are not surfaced here). Returns zeros before [init].
  static Map<String, int> debugStats() {
    try {
      final gate = _gate;
      final host = _host;
      // 1 once uploads terminally halt on a 401 (bad/rotated write key). Makes
      // an auth halt observable off the engine isolate (Rule 0.3) — otherwise
      // capture keeps climbing while nothing ships and the SDK looks healthy.
      final uploadHalted = switch (host) {
        final HaltAware h => h.authHalted,
        _ => false,
      };
      return {
        'captured': gate?.capturedTotal ?? 0,
        'buffered': gate?.bufferedEvents ?? 0,
        'dropped': gate?.droppedTotal ?? 0,
        'internal_errors': _internalErrors,
        'enabled': _enabled ? 1 : 0,
        'upload_halted': uploadHalted ? 1 : 0,
      };
    } on Object {
      return const {};
    }
  }

  /// Initializes the SDK. Cheap and synchronous on the main isolate (Rule 0.5);
  /// the heavy work (isolate spawn, disk open, config fetch) is async and off
  /// the first frame. Idempotent: a second call is a no-op.
  ///
  /// [host], [platform], [uuid], [nowMs], and [drainInterval] are test seams.
  static Future<void> init(
    SessionlyConfig config, {
    EngineHost? host,
    SessionlyPlatform? platform,
    UuidV7Generator? uuid,
    int Function()? nowMs,
    Duration? drainInterval,
    bool? installAutoCapture,
    bool spawnWatchdog = true,
    bool? perfMetricsTrustworthy,
  }) async {
    if (_initialized) return;
    _initialized = true;
    _config = config;
    _enabled = config.enabled;
    _internalErrors = 0;
    _exposedFlags.clear();
    _exposedExperiments.clear();
    final buffer = RingBuffer<Map<String, Object?>>(
      maxEvents: config.memoryBufferMaxEvents,
      maxBytes: config.memoryBufferBytes,
    );
    final gate = CaptureGate(
      buffer: buffer,
      sink: _dispatch,
      uuid: uuid ?? defaultUuidV7Generator,
      nowMs: nowMs,
      drainInterval: drainInterval ?? const Duration(seconds: 1),
      onError: _onError,
    );
    _gate = gate;
    _ready = _bringUp(
      config,
      host,
      platform,
      gate,
      nowMs: nowMs,
      installAutoCapture: installAutoCapture,
      spawnWatchdog: spawnWatchdog,
      perfMetricsTrustworthy: perfMetricsTrustworthy,
    );
    await _ready;
  }

  static Future<void> _bringUp(
    SessionlyConfig config,
    EngineHost? injected,
    SessionlyPlatform? platform,
    CaptureGate gate, {
    int Function()? nowMs,
    bool? installAutoCapture,
    bool spawnWatchdog = true,
    bool? perfMetricsTrustworthy,
  }) async {
    // Master kill switch (docs/05, config.enabled): when off, the SDK installs
    // no surfaces and spawns no engine isolate, so it adds zero main-thread
    // cost and every capture entry below is a no-op.
    if (!config.enabled) return;
    try {
      _host =
          injected ??
          await IsolateEngineHost.spawn(
            config,
            platform ?? const DefaultSessionlyPlatform(),
          );
      gate.start();
      _httpTracker = SessionlyHttpTracker(
        sink: GateCaptureSink(gate: gate, onError: _onError),
        screen: () => _captureRuntime?.tracker.current,
        thresholdMs: () => config.httpSlowThresholdMs,
      );
    } on Object {
      _internalErrors++;
    }
    // Auto-capture surfaces install only when a Flutter binding is live (a real
    // app or a widget test), and never break init if a surface fails.
    if (installAutoCapture ?? _bindingReady()) {
      try {
        _captureRuntime = await CaptureRuntime.install(
          sink: GateCaptureSink(gate: gate, onError: _onError),
          config: config,
          nowMs: nowMs,
          flushHint: flush,
          spawnWatchdog: spawnWatchdog,
          perfMetricsTrustworthy: perfMetricsTrustworthy,
        );
      } on Object {
        _internalErrors++;
      }
    }
  }

  static bool _bindingReady() {
    try {
      // Accessing `.instance` throws a FlutterError if no binding is live.
      final _ = WidgetsBinding.instance;
      return true;
    } on Object {
      return false;
    }
  }

  static void _dispatch(List<Map<String, Object?>> records) {
    _host?.submit(records);
  }

  static void _onError(Object error) {
    _internalErrors++;
  }

  /// Records a developer-defined event (`type: custom`).
  static void track(String name, {Map<String, Object?>? props}) {
    if (!_enabled) return;
    _guard(() {
      _gate?.captureEvent(
        type: EventType.custom.name,
        name: name,
        props: props ?? const {},
      );
    });
  }

  /// Records a screen view (`type: auto`, `screen_view`) — a manual override
  /// for when the navigator observer is not in use.
  static void screen(String name) {
    if (!_enabled) return;
    _guard(() {
      _gate?.captureEvent(
        type: EventType.auto.name,
        name: 'screen_view',
        props: const {},
        screen: name,
      );
    });
  }

  /// Associates the current device with [userId].
  static void identify(String userId) {
    if (!_enabled) return;
    _guard(() => _gate?.captureIdentify(userId));
  }

  /// Clears identity on logout.
  static void reset() {
    if (!_enabled) return;
    _guard(() => _gate?.captureReset());
  }

  /// Reads a delivered feature flag (docs/06 § in-app flag channel). Synchronous,
  /// O(1), never throws, and default-off when the key is absent or before the
  /// first config fetch has landed. The FIRST read of a key this run emits an
  /// `auto/flag_exposure` event (deduped in-SDK) so exposures are measurable.
  static SessionlyFlag flag(String key) {
    if (!_enabled) return const SessionlyFlag(enabled: false);
    var result = const SessionlyFlag(enabled: false);
    _guard(() {
      final map = switch (_host) {
        final FlagAware h => h.flags,
        _ => const <String, Object?>{},
      };
      final entry = map[key];
      final enabled = entry is Map && entry['enabled'] == true;
      final value = entry is Map ? entry['value'] : null;
      result = SessionlyFlag(enabled: enabled, value: value);
      _recordExposure(key, enabled, value);
    });
    return result;
  }

  /// Whether a feature flag is enabled — the boolean convenience over [flag]
  /// (default-off when absent / not yet delivered). Records exposure like [flag].
  static bool isEnabled(String key) => flag(key).enabled;

  /// Resolves this actor's variant for a running experiment (docs/10 Suite
  /// modules). Synchronous, O(1), and never throws. Assignment is
  /// deterministic — `hash(anonymous_id, key)` bucketed by variant weight — so
  /// it is sticky per actor with no stored state. Returns
  /// [SessionlyExperiment.unassigned] when the experiment is absent, not yet
  /// delivered, not running, or before the actor seed lands. The FIRST assigned
  /// read of a key this run emits an `auto/experiment_exposure` event (deduped
  /// in-SDK) so exposures are measurable as ordinary events — readouts are
  /// ordinary funnels/segments.
  static SessionlyExperiment experiment(String key) {
    if (!_enabled) return SessionlyExperiment.unassigned;
    var result = SessionlyExperiment.unassigned;
    _guard(() {
      final host = switch (_host) {
        final ExperimentAware h => h,
        _ => null,
      };
      if (host == null) return;
      final seed = host.assignmentSeed;
      if (seed.isEmpty) return;
      final entry = host.experiments[key];
      if (entry is! Map) return;
      final variants = entry['variants'];
      if (variants is! List) return;
      final assignment = assignExperimentVariant(seed, key, variants);
      if (assignment == null) return;
      result = SessionlyExperiment(
        variant: assignment.name,
        value: assignment.value,
      );
      _recordExperimentExposure(key, assignment.name);
    });
    return result;
  }

  /// Emits `experiment_exposure` at most once per key this run (docs/10).
  static void _recordExperimentExposure(String key, String variant) {
    if (!_exposedExperiments.add(key)) return;
    _gate?.captureEvent(
      type: EventType.auto.name,
      name: 'experiment_exposure',
      props: <String, Object?>{'key': key, 'variant': variant},
      screen: _captureRuntime?.tracker.current,
    );
  }

  /// Emits `flag_exposure` at most once per key this run (docs/06).
  static void _recordExposure(String key, bool enabled, Object? value) {
    if (!_exposedFlags.add(key)) return;
    final props = <String, Object?>{'key': key, 'enabled': enabled};
    final digest = _flagValueDigest(value);
    if (digest != null) props['value'] = digest;
    _gate?.captureEvent(
      type: EventType.auto.name,
      name: 'flag_exposure',
      props: props,
      screen: _captureRuntime?.tracker.current,
    );
  }

  /// A bounded string digest of a structured flag value for the exposure event,
  /// never the raw payload (mirrors core FLAG_VALUE_DIGEST_MAX 128, Rule 7.1).
  static String? _flagValueDigest(Object? value) {
    if (value == null) return null;
    final s = value is String ? value : jsonEncode(value);
    return s.length > 128 ? s.substring(0, 128) : s;
  }

  /// Forces an upload attempt (test/debug affordance and lifecycle hook).
  static Future<void> flush() => _guardAsync(() async {
    await _ready;
    _gate?.drainNow();
    await _host?.flush();
  });

  /// Flushes and tears the SDK down (tests and example-app exit).
  static Future<void> shutdown() => _guardAsync(() async {
    await _ready;
    await _captureRuntime?.dispose();
    _gate
      ?..drainNow()
      ..stop();
    await _host?.shutdown();
    _captureRuntime = null;
    _httpTracker = null;
    _gate = null;
    _host = null;
    _config = null;
    _ready = null;
    _initialized = false;
    _enabled = false;
  });

  static void _guard(void Function() body) {
    try {
      body();
    } on Object catch (error, stack) {
      _internalErrors++;
      if (_config?.debugRethrow ?? false) {
        Error.throwWithStackTrace(error, stack);
      }
    }
  }

  static Future<void> _guardAsync(Future<void> Function() body) async {
    try {
      await body();
    } on Object catch (error, stack) {
      _internalErrors++;
      if (_config?.debugRethrow ?? false) {
        Error.throwWithStackTrace(error, stack);
      }
    }
  }
}

/// A delivered feature flag (docs/06 § in-app flag channel): the boolean [enabled] the
/// SDK delivered plus an optional structured [value] (variant/config). Returned by
/// [Sessionly.flag]; an absent key resolves to `SessionlyFlag(enabled: false)`.
class SessionlyFlag {
  /// Creates a flag snapshot.
  const SessionlyFlag({required this.enabled, this.value});

  /// The delivered on/off state (default-off when the flag is absent).
  final bool enabled;

  /// The delivered structured value, or `null` for a plain on/off flag.
  final Object? value;
}

/// A resolved experiment assignment (docs/10 Suite modules): the assigned
/// [variant] name plus its optional structured [value]. Returned by
/// [Sessionly.experiment]; an unassigned read (absent/undelivered experiment,
/// no actor seed yet) resolves to [SessionlyExperiment.unassigned] — `variant`
/// null.
class SessionlyExperiment {
  /// Creates an assignment snapshot.
  const SessionlyExperiment({required this.variant, this.value});

  /// The sentinel for "no assignment" — `variant` is null.
  static const SessionlyExperiment unassigned = SessionlyExperiment(
    variant: null,
  );

  /// The assigned variant name, or `null` when unassigned.
  final String? variant;

  /// The assigned variant's structured value, or `null`.
  final Object? value;

  /// `true` when this actor was assigned a variant.
  bool get isAssigned => variant != null;
}

/// Discards every event — backs the no-op [Sessionly.httpTracker] returned
/// before init / when disabled.
class _DiscardSink implements CaptureSink {
  const _DiscardSink();

  @override
  void emit({
    required EventType type,
    required String name,
    Map<String, Object?> props = const {},
    String? screen,
  }) {}
}
