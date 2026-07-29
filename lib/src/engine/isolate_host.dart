/// Production [EngineHost]: spawns the dedicated background isolate and relays
/// records/flush/shutdown to it over `SendPort`s. Spawning is async so it never
/// blocks the first frame (Rule 0.5); records captured before the isolate is up
/// are buffered here and replayed once the handshake completes.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:sessionly_flutter/src/config.dart';
import 'package:sessionly_flutter/src/engine/engine_host.dart';
import 'package:sessionly_flutter/src/engine/worker/uploader.dart';
import 'package:sessionly_flutter/src/engine/worker/worker_isolate.dart';
import 'package:sessionly_flutter/src/platform/sessionly_platform.dart';

/// Spawns and drives the engine isolate.
class IsolateEngineHost
    implements EngineHost, HaltAware, FlagAware, ExperimentAware {
  IsolateEngineHost._(this._config, this._ctx, this._storageDir);

  /// Spawns the worker isolate for [config] using [platform] for the storage
  /// directory and context snapshot. Returns once the handshake completes.
  static Future<IsolateEngineHost> spawn(
    SessionlyConfig config,
    SessionlyPlatform platform,
  ) async {
    final ctx = await platform.snapshot();
    final storageDir = await platform.storageDirectory();
    final host = IsolateEngineHost._(config, ctx, storageDir);
    await host._start();
    return host;
  }

  final SessionlyConfig _config;
  final CtxSnapshot _ctx;
  final String _storageDir;

  SendPort? _worker;
  final List<List<Map<String, Object?>>> _pending = [];

  ReceivePort? _status;
  bool _authHalted = false;
  Map<String, Object?> _flags = const {};
  Map<String, Object?> _experiments = const {};
  String _seed = '';

  /// `true` once the worker reports a terminal 401 upload halt (Rule 0.3): a
  /// bad/rotated write key. Surfaced via `Sessionly.debugStats` so the halt is
  /// never silent — capture keeps flowing while nothing ships.
  @override
  bool get authHalted => _authHalted;

  /// The last delivered feature-flag map, relayed from the engine isolate's
  /// remote config over the status port (docs/06 § in-app flag channel). Read
  /// synchronously by `Sessionly.flag()`; empty until the first fetch lands.
  @override
  Map<String, Object?> get flags => _flags;

  /// The last delivered running-experiment map, relayed from the engine
  /// isolate's remote config over the status port (docs/10 Suite modules). Read
  /// synchronously by `Sessionly.experiment()`; empty until first fetch lands.
  @override
  Map<String, Object?> get experiments => _experiments;

  /// The stable actor seed relayed once after the worker's engine starts. Empty
  /// until it lands — an empty seed means `Sessionly.experiment()` assigns
  /// nothing.
  @override
  String get assignmentSeed => _seed;

  Future<void> _start() async {
    final handshake = ReceivePort();
    final ready = Completer<SendPort>();
    handshake.listen((message) {
      if (message is SendPort && !ready.isCompleted) ready.complete(message);
    });
    // A durable reverse channel for worker status (upload halt + flags).
    final status = _status = ReceivePort()
      ..listen((message) {
        if (message == WorkerMsg.authHalted) {
          _authHalted = true;
        } else if (message is List &&
            message.isNotEmpty &&
            message[0] == WorkerMsg.flags) {
          final map = message[1];
          if (map is Map) _flags = map.cast<String, Object?>();
        } else if (message is List &&
            message.isNotEmpty &&
            message[0] == WorkerMsg.experiments) {
          final map = message[1];
          if (map is Map) _experiments = map.cast<String, Object?>();
        } else if (message is List &&
            message.isNotEmpty &&
            message[0] == WorkerMsg.seed) {
          final s = message[1];
          if (s is String) _seed = s;
        }
      });
    await Isolate.spawn(workerMain, <String, Object?>{
      'port': handshake.sendPort,
      'status_port': status.sendPort,
      'storage_dir': _storageDir,
      'endpoint': _config.endpoint.toString(),
      'write_key': _config.writeKey,
      'batch_size': _config.flushBatchSize,
      'flush_interval_s': _config.flushIntervalSeconds,
      'session_timeout_ms': _config.sessionTimeoutMinutes * 60 * 1000,
      'disk_bytes': _config.diskQueueBytes,
      'sdk_version': sessionlySdkVersion,
      'ctx': _ctx.toMap(),
    });
    _worker = await ready.future;
    // The handshake is one-shot; close it so it does not keep a live port.
    handshake.close();
    for (final batch in _pending) {
      _worker!.send([WorkerMsg.records, batch]);
    }
    _pending.clear();
  }

  @override
  void submit(List<Map<String, Object?>> records) {
    final worker = _worker;
    if (worker == null) {
      _pending.add(records);
    } else {
      worker.send([WorkerMsg.records, records]);
    }
  }

  @override
  Future<void> flush() async {
    final worker = _worker;
    if (worker == null) return;
    final reply = ReceivePort();
    worker.send([WorkerMsg.flush, reply.sendPort]);
    await reply.first;
    reply.close();
  }

  @override
  Future<void> shutdown() async {
    final worker = _worker;
    if (worker == null) return;
    final reply = ReceivePort();
    worker.send([WorkerMsg.shutdown, reply.sendPort]);
    await reply.first;
    reply.close();
    _status?.close();
    _status = null;
  }
}
