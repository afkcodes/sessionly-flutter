/// The event vocabulary: the fixed `name` set governed per non-custom `type`,
/// mirroring `packages/core/src/protocol/v1/vocabulary.ts` exactly (Rule 2.1).
///
/// Additive-only (Rule 2.3): names may be appended, never renamed or removed.
/// This table is the extension point (Rule 4.10) — a new governed event is a
/// new entry here, never an edit to a consumer.
library;

/// The eight top-level event types.
enum EventType {
  /// Auto-captured interaction events (screen views, taps, ...).
  auto,

  /// Developer-defined events via `Sessionly.track`.
  custom,

  /// App/session lifecycle transitions.
  lifecycle,

  /// Error and crash events.
  error,

  /// On-device frustration-signal detectors.
  frustration,

  /// Performance observer events.
  perf,

  /// Identity resolution events.
  identity,

  /// Monetary revenue events (server- or client-reported purchases).
  revenue;

  /// Resolves an [EventType] from its wire string, or `null` if unknown.
  static EventType? fromWire(String wire) {
    for (final type in EventType.values) {
      if (type.name == wire) return type;
    }
    return null;
  }
}

/// Auto-capture event names.
const Set<String> autoNames = {
  'screen_view',
  'tap',
  'scroll_depth',
  'input_focus',
  'input_abandon',
  'navigation',
  'flag_exposure',
  'experiment_exposure',
};

/// Lifecycle event names.
const Set<String> lifecycleNames = {
  'app_open',
  'app_foreground',
  'app_background',
  'session_start',
  'session_end',
  'first_open',
};

/// Frustration detector event names.
const Set<String> frustrationNames = {
  'rage_tap',
  'dead_tap',
  'nav_thrash',
  'retry_burst',
};

/// Error event names. `js_error` is the web additive name (docs/05).
const Set<String> errorNames = {
  'crash',
  'flutter_error',
  'http_error',
  'js_error',
};

/// Performance event names. `web_vital` is the web additive name (docs/05).
const Set<String> perfNames = {
  'slow_frame_burst',
  'frozen_frame',
  'slow_screen_load',
  'http_slow',
  'web_vital',
};

/// Identity event names.
const Set<String> identityNames = {'identify', 'alias', 'reset'};

/// Revenue event names. `purchase` covers one-off and recurring alike (the
/// `recurring` prop distinguishes them); future names (e.g. refund) append
/// here.
const Set<String> revenueNames = {'purchase'};

/// Governed `type` → allowed `name` set. `custom` is absent: its names are
/// developer-defined (non-empty, ≤ [customNameMaxLength]).
const Map<EventType, Set<String>> eventVocabulary = {
  EventType.auto: autoNames,
  EventType.lifecycle: lifecycleNames,
  EventType.frustration: frustrationNames,
  EventType.error: errorNames,
  EventType.perf: perfNames,
  EventType.identity: identityNames,
  EventType.revenue: revenueNames,
};

/// Max length of a `custom` event name accepted on the wire.
const int customNameMaxLength = 128;

/// Recommended shape for custom names — snake_case starting with a letter.
final RegExp recommendedCustomNameRegex = RegExp(r'^[a-z][a-z0-9_]*$');

/// `true` iff [name] belongs to the closed vocabulary of governed [type].
bool isVocabularyName(EventType type, String name) =>
    eventVocabulary[type]?.contains(name) ?? false;

/// `true` iff a custom [name] follows the recommended snake_case convention and
/// length cap. Non-conforming names are still accepted on the wire — this is a
/// hygiene helper, not a validator.
bool isRecommendedCustomName(String name) =>
    name.isNotEmpty &&
    name.length <= customNameMaxLength &&
    recommendedCustomNameRegex.hasMatch(name);
