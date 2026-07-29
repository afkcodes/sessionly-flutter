part of 'event.dart';

// Concrete event branches for the sealed [SessionlyEvent] hierarchy. Split
// from event.dart to keep each file within the 400-line cap (Rule 4.8).

/// Auto-captured interaction event (`type: auto`).
final class AutoEvent extends SessionlyEvent {
  /// Creates an [AutoEvent]. [name] must be in [autoNames].
  const AutoEvent({
    required super.eventId,
    required super.ts,
    required super.sessionId,
    required super.anonymousId,
    required super.userId,
    required super.screen,
    required super.props,
    required super.ctx,
    required super.name,
  });

  /// Parses an [AutoEvent] from JSON at [path].
  factory AutoEvent.fromJson(
    Map<String, Object?> json, {
    String path = '',
  }) {
    final c = _readCommon(json, path);
    final name = _governedName(json, autoNames, path);
    validateCaptureProps(
      EventType.auto,
      name,
      c.props,
      childPath(path, 'props'),
    );
    return AutoEvent(
      eventId: c.eventId,
      ts: c.ts,
      sessionId: c.sessionId,
      anonymousId: c.anonymousId,
      userId: c.userId,
      screen: c.screen,
      props: c.props,
      ctx: c.ctx,
      name: name,
    );
  }

  @override
  EventType get type => EventType.auto;
}

/// Lifecycle event (`type: lifecycle`).
final class LifecycleEvent extends SessionlyEvent {
  /// Creates a [LifecycleEvent]. [name] must be in [lifecycleNames].
  const LifecycleEvent({
    required super.eventId,
    required super.ts,
    required super.sessionId,
    required super.anonymousId,
    required super.userId,
    required super.screen,
    required super.props,
    required super.ctx,
    required super.name,
  });

  /// Parses a [LifecycleEvent] from JSON at [path].
  factory LifecycleEvent.fromJson(
    Map<String, Object?> json, {
    String path = '',
  }) {
    final c = _readCommon(json, path);
    return LifecycleEvent(
      eventId: c.eventId,
      ts: c.ts,
      sessionId: c.sessionId,
      anonymousId: c.anonymousId,
      userId: c.userId,
      screen: c.screen,
      props: c.props,
      ctx: c.ctx,
      name: _governedName(json, lifecycleNames, path),
    );
  }

  @override
  EventType get type => EventType.lifecycle;
}

/// Frustration detector event (`type: frustration`).
final class FrustrationEvent extends SessionlyEvent {
  /// Creates a [FrustrationEvent]. [name] must be in [frustrationNames].
  const FrustrationEvent({
    required super.eventId,
    required super.ts,
    required super.sessionId,
    required super.anonymousId,
    required super.userId,
    required super.screen,
    required super.props,
    required super.ctx,
    required super.name,
  });

  /// Parses a [FrustrationEvent] from JSON at [path].
  factory FrustrationEvent.fromJson(
    Map<String, Object?> json, {
    String path = '',
  }) {
    final c = _readCommon(json, path);
    final name = _governedName(json, frustrationNames, path);
    validateCaptureProps(
      EventType.frustration,
      name,
      c.props,
      childPath(path, 'props'),
    );
    return FrustrationEvent(
      eventId: c.eventId,
      ts: c.ts,
      sessionId: c.sessionId,
      anonymousId: c.anonymousId,
      userId: c.userId,
      screen: c.screen,
      props: c.props,
      ctx: c.ctx,
      name: name,
    );
  }

  @override
  EventType get type => EventType.frustration;
}

/// Error / crash event (`type: error`).
final class ErrorEvent extends SessionlyEvent {
  /// Creates an [ErrorEvent]. [name] must be in [errorNames].
  const ErrorEvent({
    required super.eventId,
    required super.ts,
    required super.sessionId,
    required super.anonymousId,
    required super.userId,
    required super.screen,
    required super.props,
    required super.ctx,
    required super.name,
  });

  /// Parses an [ErrorEvent] from JSON at [path].
  factory ErrorEvent.fromJson(
    Map<String, Object?> json, {
    String path = '',
  }) {
    final c = _readCommon(json, path);
    return ErrorEvent(
      eventId: c.eventId,
      ts: c.ts,
      sessionId: c.sessionId,
      anonymousId: c.anonymousId,
      userId: c.userId,
      screen: c.screen,
      props: c.props,
      ctx: c.ctx,
      name: _governedName(json, errorNames, path),
    );
  }

  @override
  EventType get type => EventType.error;
}

/// Performance observer event (`type: perf`).
final class PerfEvent extends SessionlyEvent {
  /// Creates a [PerfEvent]. [name] must be in [perfNames].
  const PerfEvent({
    required super.eventId,
    required super.ts,
    required super.sessionId,
    required super.anonymousId,
    required super.userId,
    required super.screen,
    required super.props,
    required super.ctx,
    required super.name,
  });

  /// Parses a [PerfEvent] from JSON at [path].
  factory PerfEvent.fromJson(
    Map<String, Object?> json, {
    String path = '',
  }) {
    final c = _readCommon(json, path);
    final name = _governedName(json, perfNames, path);
    validateCaptureProps(
      EventType.perf,
      name,
      c.props,
      childPath(path, 'props'),
    );
    return PerfEvent(
      eventId: c.eventId,
      ts: c.ts,
      sessionId: c.sessionId,
      anonymousId: c.anonymousId,
      userId: c.userId,
      screen: c.screen,
      props: c.props,
      ctx: c.ctx,
      name: name,
    );
  }

  @override
  EventType get type => EventType.perf;
}

/// Identity resolution event (`type: identity`).
final class IdentityEvent extends SessionlyEvent {
  /// Creates an [IdentityEvent]. [name] must be in [identityNames].
  const IdentityEvent({
    required super.eventId,
    required super.ts,
    required super.sessionId,
    required super.anonymousId,
    required super.userId,
    required super.screen,
    required super.props,
    required super.ctx,
    required super.name,
  });

  /// Parses an [IdentityEvent] from JSON at [path].
  factory IdentityEvent.fromJson(
    Map<String, Object?> json, {
    String path = '',
  }) {
    final c = _readCommon(json, path);
    return IdentityEvent(
      eventId: c.eventId,
      ts: c.ts,
      sessionId: c.sessionId,
      anonymousId: c.anonymousId,
      userId: c.userId,
      screen: c.screen,
      props: c.props,
      ctx: c.ctx,
      name: _governedName(json, identityNames, path),
    );
  }

  @override
  EventType get type => EventType.identity;
}

/// Monetary revenue event (`type: revenue`). Unlike other branches its `props`
/// are typed on the wire: [validateRevenueProps] rejects a malformed amount /
/// currency / provider (path `…props.<field>`), never accepts-and-flags.
final class RevenueEvent extends SessionlyEvent {
  /// Creates a [RevenueEvent]. [name] must be in [revenueNames].
  const RevenueEvent({
    required super.eventId,
    required super.ts,
    required super.sessionId,
    required super.anonymousId,
    required super.userId,
    required super.screen,
    required super.props,
    required super.ctx,
    required super.name,
  });

  /// Parses a [RevenueEvent] from JSON at [path].
  factory RevenueEvent.fromJson(
    Map<String, Object?> json, {
    String path = '',
  }) {
    final c = _readCommon(json, path);
    validateRevenueProps(c.props, childPath(path, 'props'));
    return RevenueEvent(
      eventId: c.eventId,
      ts: c.ts,
      sessionId: c.sessionId,
      anonymousId: c.anonymousId,
      userId: c.userId,
      screen: c.screen,
      props: c.props,
      ctx: c.ctx,
      name: _governedName(json, revenueNames, path),
    );
  }

  @override
  EventType get type => EventType.revenue;
}

/// Developer-defined event (`type: custom`) — any non-empty name ≤ 128 chars.
final class CustomEvent extends SessionlyEvent {
  /// Creates a [CustomEvent]. [name] must be 1..[customNameMaxLength] chars.
  const CustomEvent({
    required super.eventId,
    required super.ts,
    required super.sessionId,
    required super.anonymousId,
    required super.userId,
    required super.screen,
    required super.props,
    required super.ctx,
    required super.name,
  });

  /// Parses a [CustomEvent] from JSON at [path].
  factory CustomEvent.fromJson(
    Map<String, Object?> json, {
    String path = '',
  }) {
    final c = _readCommon(json, path);
    return CustomEvent(
      eventId: c.eventId,
      ts: c.ts,
      sessionId: c.sessionId,
      anonymousId: c.anonymousId,
      userId: c.userId,
      screen: c.screen,
      props: c.props,
      ctx: c.ctx,
      name: _customName(json, path),
    );
  }

  @override
  EventType get type => EventType.custom;
}
