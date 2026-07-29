/// SDK-side sessionization (docs/05 invariant 2). A session id (UUIDv7) rotates
/// after the timeout of inactivity or on cold start; the engine synthesizes
/// `first_open`/`session_start`/`session_end` around those boundaries. The
/// server never guesses session edges.
library;

import 'package:sessionly_flutter/src/engine/worker/kv_store.dart';
import 'package:sessionly_flutter/src/protocol/uuid_v7.dart';

/// A lifecycle event the engine must synthesize at a session boundary.
class LifecyclePoint {
  /// Creates a [LifecyclePoint].
  const LifecyclePoint({
    required this.name,
    required this.sessionId,
    required this.tsMs,
    this.props = const {},
  });

  /// Lifecycle name (`first_open` / `session_start` / `session_end`).
  final String name;

  /// Session id the synthesized event belongs to.
  final String sessionId;

  /// Timestamp (Unix ms).
  final int tsMs;

  /// Extra props (e.g. `{end_reason: timeout}`).
  final Map<String, Object?> props;
}

/// The result of registering activity: the session to stamp the triggering
/// event with, plus any lifecycle events to emit first.
class SessionTouch {
  /// Creates a [SessionTouch].
  const SessionTouch({required this.sessionId, required this.synthetic});

  /// Session id for the triggering event.
  final String sessionId;

  /// Lifecycle events to emit before the triggering event.
  final List<LifecyclePoint> synthetic;
}

/// Owns session state (id, last activity, first-open flag), persisted to the
/// [KvStore] so a session survives process restarts within the timeout window.
class Sessionizer {
  /// Creates a sessionizer over [kv], rotating after [timeoutMs] inactivity.
  Sessionizer({
    required KvStore kv,
    required UuidV7Generator uuid,
    required int timeoutMs,
  }) : _kv = kv,
       _uuid = uuid,
       _timeoutMs = timeoutMs;

  final KvStore _kv;
  final UuidV7Generator _uuid;
  final int _timeoutMs;

  String? _sessionId;
  int _lastActivityMs = 0;
  bool _firstOpenDone = false;

  /// Current session id, or `null` before the first touch.
  String? get sessionId => _sessionId;

  /// Loads persisted state. Call once before the first [touch].
  Future<void> load() async {
    _sessionId = await _kv.get(KvKey.sessionId);
    _lastActivityMs =
        int.tryParse(await _kv.get(KvKey.lastActivityMs) ?? '') ?? 0;
    _firstOpenDone = (await _kv.get(KvKey.firstOpenDone)) == '1';
  }

  /// Registers activity at [nowMs], rotating the session if needed and
  /// returning the session id plus any synthesized boundary events.
  Future<SessionTouch> touch(int nowMs) async {
    final synthetic = <LifecyclePoint>[];
    final expired = _sessionId != null && nowMs - _lastActivityMs > _timeoutMs;
    if (_sessionId == null || expired) {
      if (expired) {
        synthetic.add(
          LifecyclePoint(
            name: 'session_end',
            sessionId: _sessionId!,
            tsMs: nowMs,
            props: const {'end_reason': 'timeout'},
          ),
        );
      }
      final id = _uuid.generate();
      if (!_firstOpenDone) {
        synthetic.add(
          LifecyclePoint(name: 'first_open', sessionId: id, tsMs: nowMs),
        );
        _firstOpenDone = true;
      }
      synthetic.add(
        LifecyclePoint(name: 'session_start', sessionId: id, tsMs: nowMs),
      );
      _sessionId = id;
    }
    _lastActivityMs = nowMs;
    await _persist();
    return SessionTouch(sessionId: _sessionId!, synthetic: synthetic);
  }

  /// Explicitly ends the current session (background/exit), returning the
  /// `session_end` point to emit, or `null` if no session is active. The next
  /// [touch] cold-starts a fresh session.
  Future<LifecyclePoint?> endSession(int nowMs, String reason) async {
    final id = _sessionId;
    if (id == null) return null;
    _sessionId = null;
    await _persist();
    return LifecyclePoint(
      name: 'session_end',
      sessionId: id,
      tsMs: nowMs,
      props: {'end_reason': reason},
    );
  }

  Future<void> _persist() async {
    final id = _sessionId;
    if (id == null) {
      await _kv.remove(KvKey.sessionId);
    } else {
      await _kv.set(KvKey.sessionId, id);
    }
    await _kv.set(KvKey.lastActivityMs, '$_lastActivityMs');
    await _kv.set(KvKey.firstOpenDone, _firstOpenDone ? '1' : '0');
  }
}
