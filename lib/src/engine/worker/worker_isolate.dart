/// The dedicated background isolate entrypoint (docs/05 threading model). This
/// is the only place the heavy collaborators (sqlite, http) are constructed;
/// they never touch the main isolate. Messages in/out are primitives + SendPorts
/// only — no custom objects cross the port.
library;

import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:sessionly_flutter/src/engine/engine.dart';
import 'package:sessionly_flutter/src/engine/telemetry.dart';
import 'package:sessionly_flutter/src/engine/worker/disk_queue.dart';
import 'package:sessionly_flutter/src/engine/worker/identity.dart';
import 'package:sessionly_flutter/src/engine/worker/remote_config.dart';
import 'package:sessionly_flutter/src/engine/worker/scrubber.dart';
import 'package:sessionly_flutter/src/engine/worker/sessionizer.dart';
import 'package:sessionly_flutter/src/engine/worker/uploader.dart';
import 'package:sessionly_flutter/src/platform/sessionly_platform.dart';
import 'package:sessionly_flutter/src/protocol/uuid_v7.dart';

/// Message tags exchanged with the worker isolate.
abstract final class WorkerMsg {
  /// `[records, List<Map>]` — a drained capture batch.
  static const String records = 'records';

  /// `[flush, SendPort]` — flush and reply when settled.
  static const String flush = 'flush';

  /// `[shutdown, SendPort]` — shut down and reply.
  static const String shutdown = 'shutdown';

  /// `[ctx, Map]` — updated context snapshot.
  static const String ctx = 'ctx';

  /// Sent alone on the status port when uploads terminally halt on a 401.
  static const String authHalted = 'auth_halted';

  /// `[flags, Map]` on the status port — the delivered flag map, relayed to the
  /// main isolate so `Sessionly.flag()` reads it (docs/06).
  static const String flags = 'flags';

  /// `[experiments, Map]` on the status port — the delivered running-experiment
  /// map, relayed to the main isolate so `Sessionly.experiment()` reads it (docs/10).
  static const String experiments = 'experiments';

  /// `[seed, String]` on the status port — the stable actor id used as the
  /// deterministic assignment seed, relayed once after engine start (docs/10).
  static const String seed = 'seed';
}

/// The isolate entrypoint. [init] carries the handshake `SendPort` plus all
/// primitive config the engine needs to build itself locally.
Future<void> workerMain(Map<String, Object?> init) async {
  final handshake = init['port']! as SendPort;
  final statusPort = init['status_port'] as SendPort?;
  final inbox = ReceivePort();
  handshake.send(inbox.sendPort);

  final store = SqliteStore.open(
    '${init['storage_dir']! as String}/sessionly.db',
    maxBytes: init['disk_bytes']! as int,
  );
  final client = http.Client();
  final uuid = UuidV7Generator();
  final endpoint = Uri.parse(init['endpoint']! as String);
  final writeKey = init['write_key']! as String;
  final telemetry = Telemetry();

  final engine = Engine(
    telemetry: telemetry,
    sessionizer: Sessionizer(
      kv: store.kv,
      uuid: uuid,
      timeoutMs: init['session_timeout_ms']! as int,
    ),
    identity: IdentityStore(kv: store.kv, uuid: uuid),
    scrubber: const NoopScrubber(),
    queue: store,
    uploader: Uploader(
      client: client,
      queue: store,
      endpoint: endpoint,
      writeKey: writeKey,
      telemetry: telemetry,
      nowMs: _systemNowMs,
      batchSize: init['batch_size']! as int,
      flushInterval: Duration(seconds: init['flush_interval_s']! as int),
      onHalt: () => statusPort?.send(WorkerMsg.authHalted),
    ),
    remoteConfig: RemoteConfig(
      client: client,
      endpoint: endpoint,
      writeKey: writeKey,
      kv: store.kv,
      onFlags: (flags) => statusPort?.send([WorkerMsg.flags, flags]),
      onExperiments: (experiments) =>
          statusPort?.send([WorkerMsg.experiments, experiments]),
    ),
    uuid: uuid,
    ctx: CtxSnapshot.fromMap(
      (init['ctx']! as Map).cast<String, Object?>(),
    ),
    batchSize: init['batch_size']! as int,
    nowMs: _systemNowMs,
  );
  await engine.start();
  // Relay the stable assignment seed once identity has loaded, so the main
  // isolate can resolve experiment variants deterministically (docs/10).
  statusPort?.send([WorkerMsg.seed, engine.anonymousId]);

  await for (final message in inbox) {
    final parts = message as List;
    switch (parts[0]) {
      case WorkerMsg.records:
        await engine.submit(
          (parts[1] as List).cast<Map<String, Object?>>(),
        );
      case WorkerMsg.ctx:
        engine.ctx = CtxSnapshot.fromMap(
          (parts[1] as Map).cast<String, Object?>(),
        );
      case WorkerMsg.flush:
        await engine.flush();
        (parts[1] as SendPort).send(null);
      case WorkerMsg.shutdown:
        await engine.shutdown();
        (parts[1] as SendPort).send(null);
        client.close();
        inbox.close();
    }
  }
}

int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;
