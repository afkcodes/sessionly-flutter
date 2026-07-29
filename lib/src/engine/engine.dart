/// The engine: everything right of the ring buffer (docs/05 pipeline). It runs
/// off the main isolate — in production inside a dedicated background isolate,
/// in tests directly. It turns raw capture records into protocol events
/// (sessionize, identity, scrub, validate), persists them to the disk queue,
/// and drives the uploader. Pure Dart: no Flutter plugins reach this class.
library;

import 'dart:convert';
import 'dart:math';

import 'package:sessionly_flutter/src/engine/capture_record.dart';
import 'package:sessionly_flutter/src/engine/telemetry.dart';
import 'package:sessionly_flutter/src/engine/worker/event_factory.dart';
import 'package:sessionly_flutter/src/engine/worker/identity.dart';
import 'package:sessionly_flutter/src/engine/worker/queue_store.dart';
import 'package:sessionly_flutter/src/engine/worker/remote_config.dart';
import 'package:sessionly_flutter/src/engine/worker/scrubber.dart';
import 'package:sessionly_flutter/src/engine/worker/sessionizer.dart';
import 'package:sessionly_flutter/src/engine/worker/uploader.dart';
import 'package:sessionly_flutter/src/platform/sessionly_platform.dart';
import 'package:sessionly_flutter/src/protocol/event.dart';
import 'package:sessionly_flutter/src/protocol/limits.dart';
import 'package:sessionly_flutter/src/protocol/uuid_v7.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

/// Orchestrates the off-main-thread pipeline.
class Engine {
  /// Creates an engine from its already-constructed collaborators.
  Engine({
    required Telemetry telemetry,
    required Sessionizer sessionizer,
    required IdentityStore identity,
    required Scrubber scrubber,
    required QueueStore queue,
    required Uploader uploader,
    required RemoteConfig remoteConfig,
    required UuidV7Generator uuid,
    required this.ctx,
    required int batchSize,
    required int Function() nowMs,
    Random? random,
  }) : _telemetry = telemetry,
       _sessionizer = sessionizer,
       _identity = identity,
       _scrubber = scrubber,
       _queue = queue,
       _uploader = uploader,
       _remoteConfig = remoteConfig,
       _uuid = uuid,
       _batchSize = batchSize,
       _nowMs = nowMs,
       _random = random ?? Random();

  final Telemetry _telemetry;
  final Sessionizer _sessionizer;
  final IdentityStore _identity;
  final Scrubber _scrubber;
  final QueueStore _queue;
  final Uploader _uploader;
  final RemoteConfig _remoteConfig;
  final UuidV7Generator _uuid;
  final int _batchSize;
  final int Function() _nowMs;
  final Random _random;

  /// Context snapshot used for `ctx` assembly; updated on network/locale change.
  CtxSnapshot ctx;
  String? _lastScreen;

  /// `true` once the uploader has terminally halted on a 401 (bad/rotated write
  /// key). Surfaced to the main isolate so the halt is observable (Rule 0.3).
  bool get authHalted => _uploader.halted;

  /// The last delivered feature-flag map (docs/06 § in-app flag channel). Read by
  /// the inline host so in-process tests exercise `Sessionly.flag()` with no
  /// spawned isolate.
  Map<String, Object?> get flags => _remoteConfig.values.flags;

  /// The last delivered running-experiment map (docs/10 Suite modules). Read by
  /// the inline host so in-process tests exercise `Sessionly.experiment()`.
  Map<String, Object?> get experiments => _remoteConfig.values.experiments;

  /// The stable per-actor anonymous id — the deterministic assignment seed for
  /// `Sessionly.experiment()` (sticky per actor). Empty until identity loads.
  String get anonymousId => _identity.anonymousId;

  /// Loads durable state and starts background timers. Non-blocking with
  /// respect to the first frame: callers `unawaited` it.
  Future<void> start() async {
    await _identity.load();
    await _sessionizer.load();
    await _remoteConfig.start();
    _uploader.start();
    // A prior run may have left queued rows — resume immediately.
    await _uploader.pumpAll();
  }

  /// Processes a drained batch of raw records.
  Future<void> submit(List<Map<String, Object?>> records) async {
    final pending = <String>[];
    for (final record in records) {
      await _process(record, pending);
    }
    await _emitTelemetry(pending);
    if (pending.isNotEmpty) {
      final evicted = await _queue.enqueue(pending, nowMs: _nowMs());
      _telemetry.droppedDisk += evicted;
    }
    if (await _queue.count() >= _batchSize) {
      await _uploader.pumpAll();
    }
  }

  Future<void> _process(
    Map<String, Object?> record,
    List<String> pending,
  ) async {
    final kind = record[RecordKey.kind];
    if (kind == RecordKind.meta) {
      _telemetry.droppedBuffer +=
          (record[RecordKey.droppedBuffer] as int?) ?? 0;
      return;
    }
    // Kill switch: capture is a no-op while remote config disables the SDK.
    if (!_remoteConfig.enabled) return;
    switch (kind) {
      case RecordKind.event:
        await _processEvent(record, pending);
      case RecordKind.identify:
        await _processIdentify(record, pending);
      case RecordKind.reset:
        await _processReset(record, pending);
    }
  }

  Future<void> _processEvent(
    Map<String, Object?> record,
    List<String> pending,
  ) async {
    if (_random.nextDouble() > _remoteConfig.values.sampleRate) return;
    final tsMs = record[RecordKey.tsMs]! as int;
    final touch = await _sessionizer.touch(tsMs);
    _addSynthetic(touch.synthetic, pending);
    final screen = record[RecordKey.screen] as String?;
    if (screen != null) _lastScreen = screen;
    var props = (record[RecordKey.props]! as Map).cast<String, Object?>();
    props = _scrubber.scrub(record[RecordKey.name]! as String, props);
    if (!validateProps(props).isValid) {
      _telemetry.invalidProps++;
      return;
    }
    pending.add(
      jsonEncode(
        _build(
          eventId: record[RecordKey.eventId]! as String,
          tsMs: tsMs,
          type: record[RecordKey.type]! as String,
          name: record[RecordKey.name]! as String,
          props: props,
          screen: screen ?? _lastScreen,
          sessionId: touch.sessionId,
        ).toJson(),
      ),
    );
  }

  Future<void> _processIdentify(
    Map<String, Object?> record,
    List<String> pending,
  ) async {
    final tsMs = record[RecordKey.tsMs]! as int;
    final touch = await _sessionizer.touch(tsMs);
    _addSynthetic(touch.synthetic, pending);
    final userId = record[RecordKey.userId]! as String;
    await _identity.identify(userId);
    pending.add(
      jsonEncode(
        _build(
          eventId: record[RecordKey.eventId]! as String,
          tsMs: tsMs,
          type: EventType.identity.name,
          name: 'identify',
          props: const {},
          screen: _lastScreen,
          sessionId: touch.sessionId,
        ).toJson(),
      ),
    );
  }

  Future<void> _processReset(
    Map<String, Object?> record,
    List<String> pending,
  ) async {
    final tsMs = record[RecordKey.tsMs]! as int;
    final touch = await _sessionizer.touch(tsMs);
    _addSynthetic(touch.synthetic, pending);
    // Stamp the reset event with the identity being cleared, then rotate.
    pending.add(
      jsonEncode(
        _build(
          eventId: record[RecordKey.eventId]! as String,
          tsMs: tsMs,
          type: EventType.identity.name,
          name: 'reset',
          props: const {},
          screen: _lastScreen,
          sessionId: touch.sessionId,
        ).toJson(),
      ),
    );
    await _identity.reset();
  }

  void _addSynthetic(List<LifecyclePoint> points, List<String> pending) {
    for (final point in points) {
      pending.add(
        jsonEncode(
          _build(
            eventId: _uuid.generate(),
            tsMs: point.tsMs,
            type: EventType.lifecycle.name,
            name: point.name,
            props: point.props,
            screen: _lastScreen,
            sessionId: point.sessionId,
          ).toJson(),
        ),
      );
    }
  }

  Future<void> _emitTelemetry(List<String> pending) async {
    final props = _telemetry.maybeDrain(_nowMs());
    if (props == null) return;
    final touch = await _sessionizer.touch(_nowMs());
    _addSynthetic(touch.synthetic, pending);
    pending.add(
      jsonEncode(
        _build(
          eventId: _uuid.generate(),
          tsMs: _nowMs(),
          type: EventType.custom.name,
          name: 'sdk_health',
          props: props,
          screen: _lastScreen,
          sessionId: touch.sessionId,
        ).toJson(),
      ),
    );
  }

  SessionlyEvent _build({
    required String eventId,
    required int tsMs,
    required String type,
    required String name,
    required Map<String, Object?> props,
    required String? screen,
    required String sessionId,
  }) => buildEvent(
    type: type,
    name: name,
    eventId: eventId,
    ts: DateTime.fromMillisecondsSinceEpoch(tsMs, isUtc: true),
    sessionId: sessionId,
    anonymousId: _identity.anonymousId,
    userId: _identity.userId,
    screen: screen,
    props: props,
    ctx: ctx.toCtx(),
  );

  /// Flushes pending telemetry and drains the disk queue.
  Future<void> flush() async {
    final pending = <String>[];
    await _emitTelemetry(pending);
    if (pending.isNotEmpty) {
      await _queue.enqueue(pending, nowMs: _nowMs());
    }
    await _uploader.pumpAll();
  }

  /// Ends the session, flushes, stops timers, and closes resources.
  Future<void> shutdown() async {
    final point = await _sessionizer.endSession(_nowMs(), 'app_exit');
    if (point != null) {
      final pending = <String>[];
      _addSynthetic([point], pending);
      await _queue.enqueue(pending, nowMs: _nowMs());
    }
    await _uploader.pumpAll();
    _uploader.stop();
    _remoteConfig.stop();
    await _queue.close();
  }
}
