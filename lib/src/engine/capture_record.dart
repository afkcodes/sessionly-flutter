/// The port-transferable "raw capture record": the only thing that crosses from
/// the main isolate into the engine. It is a plain `Map` of primitives — no
/// custom objects, no expensive copies (docs/05 threading contract).
library;

/// Record `kind` discriminators.
abstract final class RecordKind {
  /// A developer `track(...)` or auto-captured event.
  static const String event = 'event';

  /// `identify(userId)`.
  static const String identify = 'identify';

  /// `reset()`.
  static const String reset = 'reset';

  /// Main-isolate meta (e.g. ring-buffer drop deltas) folded into telemetry.
  static const String meta = 'meta';
}

/// Well-known keys in a raw capture record.
abstract final class RecordKey {
  /// Discriminator, one of [RecordKind].
  static const String kind = 'k';

  /// Client UUIDv7, stamped at capture time.
  static const String eventId = 'event_id';

  /// Capture time in Unix ms, stamped at capture time.
  static const String tsMs = 'ts';

  /// Protocol event `type` (for [RecordKind.event]).
  static const String type = 'type';

  /// Protocol event `name`.
  static const String name = 'name';

  /// Event props.
  static const String props = 'props';

  /// Current screen, or `null`.
  static const String screen = 'screen';

  /// User id (for [RecordKind.identify]).
  static const String userId = 'user_id';

  /// Ring-buffer dropped delta (for [RecordKind.meta]).
  static const String droppedBuffer = 'dropped_buffer';
}

/// Builds an event record. Called on the main isolate, so it does no
/// serialization — just assembles primitives.
Map<String, Object?> eventRecord({
  required String eventId,
  required int tsMs,
  required String type,
  required String name,
  required Map<String, Object?> props,
  String? screen,
}) => {
  RecordKey.kind: RecordKind.event,
  RecordKey.eventId: eventId,
  RecordKey.tsMs: tsMs,
  RecordKey.type: type,
  RecordKey.name: name,
  RecordKey.props: props,
  RecordKey.screen: screen,
};

/// Builds an `identify` record.
Map<String, Object?> identifyRecord({
  required String eventId,
  required int tsMs,
  required String userId,
}) => {
  RecordKey.kind: RecordKind.identify,
  RecordKey.eventId: eventId,
  RecordKey.tsMs: tsMs,
  RecordKey.userId: userId,
};

/// Builds a `reset` record.
Map<String, Object?> resetRecord({
  required String eventId,
  required int tsMs,
}) => {
  RecordKey.kind: RecordKind.reset,
  RecordKey.eventId: eventId,
  RecordKey.tsMs: tsMs,
};

/// Builds a `meta` record carrying a ring-buffer drop delta.
Map<String, Object?> droppedMetaRecord(int droppedDelta) => {
  RecordKey.kind: RecordKind.meta,
  RecordKey.droppedBuffer: droppedDelta,
};

/// A cheap, allocation-light byte estimate for buffer accounting. Deliberately
/// approximate (Rule 0.4 asks for *bounded*, not exact) so the capture path
/// stays O(1): it never serializes.
int estimateRecordBytes(
  String name,
  Map<String, Object?> props,
  String? screen,
) {
  var total = 160 + name.length + (screen?.length ?? 0);
  for (final entry in props.entries) {
    total += entry.key.length + 16;
    final value = entry.value;
    if (value is String) total += value.length;
  }
  return total;
}
