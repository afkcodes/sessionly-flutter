/// A single captured event, mirroring `packages/core/src/protocol/v1/event.ts`.
///
/// Modelled as a sealed hierarchy discriminated on `type`. For governed types
/// the `name` is constrained to its vocabulary; `custom` accepts any non-empty
/// name (≤ [customNameMaxLength]). The shape is closed — unknown keys are a
/// protocol violation (Rule 2.3).
library;

import 'package:sessionly_flutter/src/protocol/capture_props.dart';
import 'package:sessionly_flutter/src/protocol/ctx.dart';
import 'package:sessionly_flutter/src/protocol/errors.dart';
import 'package:sessionly_flutter/src/protocol/formats.dart';
import 'package:sessionly_flutter/src/protocol/limits.dart';
import 'package:sessionly_flutter/src/protocol/parse.dart';
import 'package:sessionly_flutter/src/protocol/revenue_props.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

part 'event_types.dart';

const Set<String> _eventKeys = {
  'event_id',
  'ts',
  'session_id',
  'anonymous_id',
  'user_id',
  'screen',
  'props',
  'ctx',
  'type',
  'name',
};

typedef _Common = ({
  String eventId,
  DateTime ts,
  String sessionId,
  String anonymousId,
  String? userId,
  String? screen,
  Map<String, Object?> props,
  EventCtx ctx,
});

_Common _readCommon(Map<String, Object?> json, String path) {
  rejectUnknownKeys(json, _eventKeys, path);
  final tsRaw = requireString(json, 'ts', path);
  return (
    eventId: requireUuidV7(json, 'event_id', path),
    ts: parseIsoDateTimeMs(tsRaw, childPath(path, 'ts')),
    sessionId: requireUuidV7(json, 'session_id', path),
    anonymousId: requireAnonymousId(json, 'anonymous_id', path),
    userId: requireNullableString(json, 'user_id', path),
    screen: requireNullableString(json, 'screen', path),
    props: requireProps(json['props'], childPath(path, 'props')),
    ctx: EventCtx.fromJson(
      requireObject(json, 'ctx', path),
      path: childPath(path, 'ctx'),
    ),
  );
}

String _governedName(
  Map<String, Object?> json,
  Set<String> allowed,
  String path,
) {
  final name = requireString(json, 'name', path);
  if (!allowed.contains(name)) {
    throw SessionlyProtocolError(
      'name "$name" is not in the governed vocabulary',
      path: childPath(path, 'name'),
    );
  }
  return name;
}

String _customName(Map<String, Object?> json, String path) {
  final name = requireString(json, 'name', path);
  if (name.length > customNameMaxLength) {
    throw SessionlyProtocolError(
      'custom name may not exceed $customNameMaxLength characters',
      path: childPath(path, 'name'),
    );
  }
  return name;
}

/// The sealed base for every captured event. Common fields are identical across
/// branches; `type` is the discriminator and `name` is branch-constrained.
sealed class SessionlyEvent {
  /// Creates an event from its common fields plus a validated [name].
  const SessionlyEvent({
    required this.eventId,
    required this.ts,
    required this.sessionId,
    required this.anonymousId,
    required this.userId,
    required this.screen,
    required this.props,
    required this.ctx,
    required this.name,
  });

  /// Parses any event from a decoded JSON map, dispatching on `type`. Throws
  /// [SessionlyProtocolError] at [path] on any violation.
  factory SessionlyEvent.fromJson(
    Map<String, Object?> json, {
    String path = '',
  }) {
    final typeWire = requireString(json, 'type', path);
    final type = EventType.fromWire(typeWire);
    return switch (type) {
      EventType.auto => AutoEvent.fromJson(json, path: path),
      EventType.lifecycle => LifecycleEvent.fromJson(json, path: path),
      EventType.frustration => FrustrationEvent.fromJson(json, path: path),
      EventType.error => ErrorEvent.fromJson(json, path: path),
      EventType.perf => PerfEvent.fromJson(json, path: path),
      EventType.identity => IdentityEvent.fromJson(json, path: path),
      EventType.revenue => RevenueEvent.fromJson(json, path: path),
      EventType.custom => CustomEvent.fromJson(json, path: path),
      null => throw SessionlyProtocolError(
        'unknown event type "$typeWire"',
        path: childPath(path, 'type'),
      ),
    };
  }

  /// Client-generated UUIDv7 (basis of idempotent ingestion, Rule 2.4).
  final String eventId;

  /// Event timestamp (UTC).
  final DateTime ts;

  /// Session UUIDv7.
  final String sessionId;

  /// Device-scoped anonymous id (`anon_`-prefixed).
  final String anonymousId;

  /// Resolved user id, or `null` when anonymous.
  final String? userId;

  /// Current screen name, or `null`.
  final String? screen;

  /// Event properties (validated against [validateProps]).
  final Map<String, Object?> props;

  /// Device / app context.
  final EventCtx ctx;

  /// Event name — governed vocabulary for non-custom types.
  final String name;

  /// The wire discriminator for this event's type.
  EventType get type;

  /// Serializes to the exact wire shape: snake_case keys, ISO-8601 millisecond
  /// UTC timestamp, and `null` preserved for nullable fields (matching the
  /// shared fixtures).
  Map<String, Object?> toJson() => {
    'event_id': eventId,
    'ts': formatIsoDateTimeMs(ts),
    'session_id': sessionId,
    'anonymous_id': anonymousId,
    'user_id': userId,
    'screen': screen,
    'props': props,
    'ctx': ctx.toJson(),
    'type': type.name,
    'name': name,
  };
}
