/// Builds a concrete [SessionlyEvent] from the engine's assembled fields. Kept
/// separate from the engine so the exhaustive type switch does not bloat the
/// orchestrator. Never hand-rolls a shape — it only routes to the P1-T6 models.
library;

import 'package:sessionly_flutter/src/protocol/ctx.dart';
import 'package:sessionly_flutter/src/protocol/event.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

/// Constructs the [SessionlyEvent] subtype for [type], carrying [name] and the
/// already-resolved common fields. Unknown/`custom` types map to [CustomEvent].
SessionlyEvent buildEvent({
  required String type,
  required String name,
  required String eventId,
  required DateTime ts,
  required String sessionId,
  required String anonymousId,
  required String? userId,
  required String? screen,
  required Map<String, Object?> props,
  required EventCtx ctx,
}) {
  return switch (EventType.fromWire(type)) {
    EventType.auto => AutoEvent(
      eventId: eventId,
      ts: ts,
      sessionId: sessionId,
      anonymousId: anonymousId,
      userId: userId,
      screen: screen,
      props: props,
      ctx: ctx,
      name: name,
    ),
    EventType.lifecycle => LifecycleEvent(
      eventId: eventId,
      ts: ts,
      sessionId: sessionId,
      anonymousId: anonymousId,
      userId: userId,
      screen: screen,
      props: props,
      ctx: ctx,
      name: name,
    ),
    EventType.identity => IdentityEvent(
      eventId: eventId,
      ts: ts,
      sessionId: sessionId,
      anonymousId: anonymousId,
      userId: userId,
      screen: screen,
      props: props,
      ctx: ctx,
      name: name,
    ),
    EventType.error => ErrorEvent(
      eventId: eventId,
      ts: ts,
      sessionId: sessionId,
      anonymousId: anonymousId,
      userId: userId,
      screen: screen,
      props: props,
      ctx: ctx,
      name: name,
    ),
    EventType.perf => PerfEvent(
      eventId: eventId,
      ts: ts,
      sessionId: sessionId,
      anonymousId: anonymousId,
      userId: userId,
      screen: screen,
      props: props,
      ctx: ctx,
      name: name,
    ),
    EventType.frustration => FrustrationEvent(
      eventId: eventId,
      ts: ts,
      sessionId: sessionId,
      anonymousId: anonymousId,
      userId: userId,
      screen: screen,
      props: props,
      ctx: ctx,
      name: name,
    ),
    EventType.revenue => RevenueEvent(
      eventId: eventId,
      ts: ts,
      sessionId: sessionId,
      anonymousId: anonymousId,
      userId: userId,
      screen: screen,
      props: props,
      ctx: ctx,
      name: name,
    ),
    EventType.custom || null => CustomEvent(
      eventId: eventId,
      ts: ts,
      sessionId: sessionId,
      anonymousId: anonymousId,
      userId: userId,
      screen: screen,
      props: props,
      ctx: ctx,
      name: name,
    ),
  };
}
