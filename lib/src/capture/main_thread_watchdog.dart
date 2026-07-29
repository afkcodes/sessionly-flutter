/// ANR proxy (docs/05): a background isolate pings the main isolate every 1 s
/// and waits for an echo. A sustained non-response (≥ 5 s) means the main
/// thread stalled; once it recovers we record the stall.
///
/// VOCABULARY MAPPING: the perf vocabulary has no `main_thread_stall` name (the
/// governed set is slow_frame_burst | frozen_frame | slow_screen_load |
/// http_slow). Adding a name is a wire-protocol change (out of scope here), so
/// a watchdog stall is emitted as `perf/frozen_frame` with
/// `props.source == "watchdog"` and `props.stall_ms`. See the task report for
/// the recommendation to add a dedicated name in a protocol revision.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:sessionly_flutter/src/capture/capture_sink.dart';
import 'package:sessionly_flutter/src/capture/current_screen.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

/// Pure stall-decision logic, isolated from the isolate plumbing so it is unit
/// testable. Fed the round-trip time of each echo; returns the stall duration
/// to report, or `null`. Reports once per stall episode (no spam): it will not
/// report again until a healthy round-trip is observed.
class WatchdogDetector {
  /// [stallThresholdMs] is the non-response duration that counts as a stall.
  WatchdogDetector({this.stallThresholdMs = 5000});

  /// Round-trip threshold (ms) above which the main thread is deemed stalled.
  final int stallThresholdMs;

  bool _reported = false;

  /// Feeds one echo's round-trip [rttMs]; returns the stall_ms to emit or null.
  int? onEcho(int rttMs) {
    if (rttMs >= stallThresholdMs) {
      if (_reported) return null;
      _reported = true;
      return rttMs;
    }
    _reported = false;
    return null;
  }
}

/// Owns the watchdog isolate and turns its stall reports into perf events.
class MainThreadWatchdog {
  /// Emits through [sink]; [tracker] supplies the screen at recovery time.
  MainThreadWatchdog({
    required CaptureSink sink,
    required CurrentScreenTracker tracker,
    this.pingInterval = const Duration(seconds: 1),
    this.stallThresholdMs = 5000,
  }) : _sink = sink,
       _tracker = tracker;

  final CaptureSink _sink;
  final CurrentScreenTracker _tracker;

  /// How often the worker pings the main isolate.
  final Duration pingInterval;

  /// Non-response threshold (ms) that counts as a stall.
  final int stallThresholdMs;

  Isolate? _worker;
  ReceivePort? _fromWorker;
  SendPort? _toWorker;

  /// Spawns the watchdog isolate and begins the ping/echo loop. Best-effort:
  /// any spawn failure is swallowed (analytics never breaks the host).
  Future<void> install() async {
    final port = ReceivePort();
    _fromWorker = port;
    port.listen(_onWorkerMessage);
    _worker = await Isolate.spawn(_watchdogMain, <String, Object?>{
      'port': port.sendPort,
      'interval_ms': pingInterval.inMilliseconds,
      'threshold_ms': stallThresholdMs,
    });
  }

  void _onWorkerMessage(Object? message) {
    if (message is SendPort) {
      _toWorker = message;
      return;
    }
    if (message is! List || message.isEmpty) return;
    final tag = message[0];
    if (tag == _kPing) {
      // Echo immediately on the main event loop; if we are stalled, the reply
      // is delayed exactly by the stall — which is what the worker measures.
      _toWorker?.send(<Object?>[_kEcho, message[1]]);
    } else if (tag == _kStall) {
      _sink.emit(
        type: EventType.perf,
        name: 'frozen_frame',
        props: {'stall_ms': message[1], 'source': 'watchdog'},
        screen: _tracker.current,
      );
    }
  }

  /// Kills the isolate and closes ports.
  void dispose() {
    _fromWorker?.close();
    _fromWorker = null;
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _toWorker = null;
  }
}

const String _kPing = 'ping';
const String _kEcho = 'echo';
const String _kStall = 'stall';

/// Worker entrypoint: pings [args]['port'] on an interval and measures the
/// round-trip of each echo, reporting stalls back over the same port.
void _watchdogMain(Map<String, Object?> args) {
  final toMain = args['port']! as SendPort;
  final intervalMs = args['interval_ms']! as int;
  final detector = WatchdogDetector(
    stallThresholdMs: args['threshold_ms']! as int,
  );
  final fromMain = ReceivePort();
  toMain.send(fromMain.sendPort);

  fromMain.listen((message) {
    if (message is! List || message.length < 2) return;
    if (message[0] != _kEcho) return;
    final sentAt = message[1]! as int;
    final rtt = DateTime.now().millisecondsSinceEpoch - sentAt;
    final stall = detector.onEcho(rtt);
    if (stall != null) toMain.send(<Object?>[_kStall, stall]);
  });

  Timer.periodic(Duration(milliseconds: intervalMs), (_) {
    toMain.send(<Object?>[_kPing, DateTime.now().millisecondsSinceEpoch]);
  });
}
