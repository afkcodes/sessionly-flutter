/// Public configuration for the Sessionly engine.
///
/// All budgets are hard-capped: a caller may lower them but never raise them
/// past the ceilings that keep Rule 0.4 (bounded resources) true.
library;

/// Auto-capture toggles. The capture surfaces themselves land in P1-T8; these
/// flags are the config seam so callers can already opt in/out per surface.
class AutoCapture {
  /// Creates an [AutoCapture] toggle set.
  const AutoCapture({
    this.screens = true,
    this.taps = true,
    this.lifecycle = true,
    this.errors = true,
    this.perf = true,
    this.scroll = true,
    this.inputs = true,
  });

  /// Everything on.
  static const AutoCapture all = AutoCapture();

  /// Everything off (manual instrumentation only).
  static const AutoCapture none = AutoCapture(
    screens: false,
    taps: false,
    lifecycle: false,
    errors: false,
    perf: false,
    scroll: false,
    inputs: false,
  );

  /// Capture screen/route views.
  final bool screens;

  /// Capture tap interactions.
  final bool taps;

  /// Capture app foreground/background lifecycle transitions.
  final bool lifecycle;

  /// Capture Flutter/platform errors.
  final bool errors;

  /// Capture frame-timing / performance signals (frames + ANR watchdog).
  final bool perf;

  /// Capture per-screen scroll depth (emitted once on screen exit).
  final bool scroll;

  /// Capture text-input focus/abandon (field identity only — never values).
  final bool inputs;
}

/// Hard ceiling on the in-memory ring buffer (Rule 0.4).
const int _memoryBytesHardCap = 8 * 1024 * 1024;

/// Hard ceiling on the on-disk queue (Rule 0.4).
const int _diskBytesHardCap = 50 * 1024 * 1024;

/// Hard ceiling on events held in memory before drop-oldest kicks in.
const int _memoryEventsHardCap = 20000;

/// Immutable engine configuration, validated and clamped on construction.
class SessionlyConfig {
  /// Creates a config. Byte/count budgets are clamped to their hard caps so a
  /// misconfiguration can never defeat the bounded-resource guarantee.
  SessionlyConfig({
    required this.writeKey,
    required this.endpoint,
    this.autoCapture = AutoCapture.all,
    this.flushIntervalSeconds = 30,
    this.flushBatchSize = 50,
    int memoryBufferBytes = 2 * 1024 * 1024,
    int memoryBufferMaxEvents = 2000,
    int diskQueueBytes = 10 * 1024 * 1024,
    this.sessionTimeoutMinutes = 30,
    this.enabled = true,
    this.debugRethrow = false,
    this.captureErrorMessages = false,
    int slowScreenLoadMs = 1000,
    int httpSlowThresholdMs = 3000,
  }) : slowScreenLoadMs = slowScreenLoadMs < 1 ? 1 : slowScreenLoadMs,
       httpSlowThresholdMs = httpSlowThresholdMs < 1 ? 1 : httpSlowThresholdMs,
       memoryBufferBytes = memoryBufferBytes.clamp(
         4 * 1024,
         _memoryBytesHardCap,
       ),
       memoryBufferMaxEvents = memoryBufferMaxEvents.clamp(
         16,
         _memoryEventsHardCap,
       ),
       diskQueueBytes = diskQueueBytes.clamp(64 * 1024, _diskBytesHardCap);

  /// Project write key, sent as `Authorization: Bearer <writeKey>`.
  final String writeKey;

  /// Ingest base endpoint (e.g. `https://fp.example.com`).
  final Uri endpoint;

  /// Auto-capture surface toggles (wired in P1-T8).
  final AutoCapture autoCapture;

  /// Upload flush cadence in seconds (Rule 0.6 default 30 s).
  final int flushIntervalSeconds;

  /// Upload flush threshold in events (Rule 0.6 default 50).
  final int flushBatchSize;

  /// In-memory ring buffer byte budget (default 2 MB, hard-capped).
  final int memoryBufferBytes;

  /// In-memory ring buffer event-count budget.
  final int memoryBufferMaxEvents;

  /// On-disk queue byte budget (default 10 MB, hard-capped).
  final int diskQueueBytes;

  /// Session inactivity rotation window (default 30 min).
  final int sessionTimeoutMinutes;

  /// Master enable. `false` makes every capture entry a no-op.
  final bool enabled;

  /// In debug builds only, rethrow swallowed internal errors so tests can see
  /// them. Always `false` in release (Rule 0.3 must hold in production).
  final bool debugRethrow;

  /// Whether error-capture may include a sanitized (length-clamped) exception
  /// message. Default `false`: only a stable message hash is sent, so raw
  /// message text — a PII risk — never leaves the device (docs/05 PII).
  final bool captureErrorMessages;

  /// Screen-load threshold in ms. A route whose first stable frame lands later
  /// than this emits `perf/slow_screen_load`; below it, nothing is recorded.
  final int slowScreenLoadMs;

  /// HTTP slow-request threshold in ms (default 3000). A request recorded via
  /// `Sessionly.httpTracker` whose duration exceeds this emits `perf/http_slow`;
  /// faster requests are dropped. A static knob like [slowScreenLoadMs] (not
  /// yet remote-tuned — see the remote-config follow-up).
  final int httpSlowThresholdMs;
}
