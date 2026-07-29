/// Sessionly Flutter SDK micro-benchmarks — the executable form of the Rule 0
/// main-thread capture budgets (docs/05 "Flutter-specific budgets").
///
/// Pure Dart: it drives only the O(1) main-isolate capture primitives
/// (`CaptureGate`, `RingBuffer`, `UuidV7Generator`), none of which touch
/// `dart:ui`, so it runs under `dart run benchmark/main.dart` on any CI runner.
/// The `dart:ui`-bound budgets (frame-timings handler, tap record+schedule) are
/// gated by `flutter test test/perf/frame_and_tap_bench_test.dart` — see PERF.md.
///
/// Budgets enforced here:
///   - capture_gate.enqueue  p99 < 1.000 ms   (Rule 0.1)
///
/// Informational (reported, never fail the gate): ring-buffer add/drain
/// throughput and UUIDv7 generation cost.
///
/// Exit code is non-zero when any enforced budget is exceeded, so this doubles
/// as the CI performance gate. Flakiness mitigation: each benchmark runs
/// `--repeats` times (default 3) and the best run is reported.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sessionly_flutter/src/engine/capture_gate.dart';
import 'package:sessionly_flutter/src/engine/capture_record.dart';
import 'package:sessionly_flutter/src/engine/ring_buffer.dart';
import 'package:sessionly_flutter/src/protocol/uuid_v7.dart';

import 'bench_stats.dart';

/// Rule 0.1: main-thread capture < 1 ms per event (p99).
const double kEnqueueBudgetMs = 1;

void main(List<String> args) {
  final opts = _Opts.parse(args);
  stdout.writeln(
    'sessionly micro-benchmarks '
    '(repeats=${opts.repeats}, iterations=${opts.iterations})',
  );

  final results = <BenchResult>[
    _benchEnqueue(opts),
    _benchRingBufferAdd(opts),
    _benchRingBufferDrain(opts),
    _benchUuid(opts),
  ];

  _printTable(results);
  _emitJson(results, opts.jsonOut);

  final failed = results.where((r) => r.enforced && !r.passed).toList();
  if (failed.isNotEmpty) {
    stderr.writeln('\nBUDGET FAILURES:');
    for (final r in failed) {
      stderr.writeln(
        '  ${r.name}: ${r.budgetMetric}=${fmtMs(r.measured!)} '
        '> budget ${fmtMs(r.budgetMs!)}',
      );
    }
    exit(1);
  }
  stdout.writeln('\nAll enforced budgets passed.');
}

// --- benchmarks -------------------------------------------------------------

/// p50/p99 of `CaptureGate.captureEvent` — the whole main-thread capture path:
/// UUIDv7 stamp + time stamp + byte estimate + O(1) ring-buffer add.
BenchResult _benchEnqueue(_Opts opts) {
  const props = {'value': 499, 'currency': 'usd', 'plan': 'pro'};
  return _bestOf(
    name: 'capture_gate.enqueue',
    repeats: opts.repeats,
    budgetMs: kEnqueueBudgetMs,
    budgetMetric: 'p99',
    note: 'captureEvent(track) — id+ts stamp + O(1) ring add',
    build: () {
      final gate = CaptureGate(
        buffer: RingBuffer<Map<String, Object?>>(
          maxEvents: 2000,
          maxBytes: 2 * 1024 * 1024,
        ),
        sink: (_) {},
        uuid: UuidV7Generator(random: Random(7)),
        drainInterval: const Duration(days: 1),
      );
      return () => gate.captureEvent(
        type: 'custom',
        name: 'checkout_completed',
        props: props,
      );
    },
    iterations: opts.iterations,
    warmup: opts.iterations ~/ 5,
  );
}

/// Isolated ring-buffer `add` cost (a component of enqueue; here in steady
/// state with drop-oldest eviction active). Informational.
BenchResult _benchRingBufferAdd(_Opts opts) {
  final record = eventRecord(
    eventId: 'x',
    tsMs: 0,
    type: 'custom',
    name: 'e',
    props: const {'a': 1},
  );
  return _bestOf(
    name: 'ring_buffer.add',
    repeats: opts.repeats,
    note: 'O(1) bounded add with drop-oldest eviction',
    build: () {
      final buffer = RingBuffer<Map<String, Object?>>(
        maxEvents: 2000,
        maxBytes: 2 * 1024 * 1024,
      );
      return () => buffer.add(record, 200);
    },
    iterations: opts.iterations,
    warmup: opts.iterations ~/ 5,
  );
}

/// Ring-buffer drain throughput: fill a full buffer, then drain it. Reports
/// events/second. Informational.
BenchResult _benchRingBufferDrain(_Opts opts) {
  const batch = 2000;
  final record = eventRecord(
    eventId: 'x',
    tsMs: 0,
    type: 'custom',
    name: 'e',
    props: const {'a': 1},
  );
  final samples = <double>[];
  var bestPerOp = double.infinity;
  var bestEventsPerSec = 0.0;
  final sw = Stopwatch()..start();
  final msPerTick = 1000.0 / sw.frequency;
  for (var r = 0; r < opts.repeats; r++) {
    final buffer = RingBuffer<Map<String, Object?>>(
      maxEvents: batch,
      maxBytes: 8 * 1024 * 1024,
    );
    for (var i = 0; i < batch; i++) {
      buffer.add(record, 200);
    }
    final t0 = sw.elapsedTicks;
    final drained = buffer.drain();
    final t1 = sw.elapsedTicks;
    final totalMs = (t1 - t0) * msPerTick;
    final perOp = totalMs / drained.length;
    if (perOp < bestPerOp) {
      bestPerOp = perOp;
      bestEventsPerSec = drained.length / (totalMs / 1000);
      samples
        ..clear()
        ..add(perOp);
    }
  }
  return BenchResult(
    name: 'ring_buffer.drain',
    stats: Stats.fromSamples(samples),
    note: 'drain $batch events; per-event cost',
    extra: {'events_per_sec': bestEventsPerSec.round()},
  );
}

/// UUIDv7 generation cost (a component of enqueue). Informational.
BenchResult _benchUuid(_Opts opts) {
  final gen = UuidV7Generator(random: Random(3));
  return _bestOf(
    name: 'uuid_v7.generate',
    repeats: opts.repeats,
    note: 'RFC 9562 UUIDv7 string',
    build: () => gen.generate,
    iterations: opts.iterations,
    warmup: opts.iterations ~/ 5,
  );
}

// --- measurement ------------------------------------------------------------

/// Times [build]'s closure over [iterations] calls, [repeats] times, keeping
/// the run with the lowest value of [budgetMetric] (default p50).
BenchResult _bestOf({
  required String name,
  required int repeats,
  required void Function() Function() build,
  required int iterations,
  required int warmup,
  double? budgetMs,
  String? budgetMetric,
  String? note,
}) {
  Stats? best;
  final metric = budgetMetric ?? 'p50';
  for (var r = 0; r < repeats; r++) {
    final body = build();
    final samples = _measurePerCall(iterations, warmup, body);
    final stats = Stats.fromSamples(samples);
    if (best == null || _metric(stats, metric) < _metric(best, metric)) {
      best = stats;
    }
  }
  return BenchResult(
    name: name,
    stats: best!,
    budgetMs: budgetMs,
    budgetMetric: budgetMetric,
    note: note,
  );
}

double _metric(Stats s, String metric) => switch (metric) {
  'p99' => s.p99Ms,
  'mean' => s.meanMs,
  'max' => s.maxMs,
  _ => s.p50Ms,
};

/// Times [body] per call for [iterations] measured calls after [warmup]
/// unmeasured calls. Uses [Stopwatch.elapsedTicks] (nanosecond-class on Linux).
List<double> _measurePerCall(int iterations, int warmup, void Function() body) {
  final sw = Stopwatch()..start();
  final msPerTick = 1000.0 / sw.frequency;
  for (var i = 0; i < warmup; i++) {
    body();
  }
  final samples = List<double>.filled(iterations, 0);
  for (var i = 0; i < iterations; i++) {
    final t0 = sw.elapsedTicks;
    body();
    final t1 = sw.elapsedTicks;
    samples[i] = (t1 - t0) * msPerTick;
  }
  return samples;
}

// --- reporting --------------------------------------------------------------

void _printTable(List<BenchResult> results) {
  stdout
    ..writeln()
    ..writeln(
      '${'benchmark'.padRight(22)}${'p50'.padLeft(12)}${'p99'.padLeft(12)}'
      '${'mean'.padLeft(12)}${'budget'.padLeft(14)}${'status'.padLeft(9)}',
    )
    ..writeln('-' * 81);
  for (final r in results) {
    final budget = r.enforced
        ? '${r.budgetMetric}<${fmtMs(r.budgetMs!)}'
        : 'info';
    final status = !r.enforced
        ? '—'
        : r.passed
        ? 'PASS'
        : 'FAIL';
    stdout.writeln(
      '${r.name.padRight(22)}'
      '${fmtMs(r.stats.p50Ms).padLeft(12)}'
      '${fmtMs(r.stats.p99Ms).padLeft(12)}'
      '${fmtMs(r.stats.meanMs).padLeft(12)}'
      '${budget.padLeft(14)}'
      '${status.padLeft(9)}',
    );
  }
}

void _emitJson(List<BenchResult> results, String? jsonOut) {
  final payload = <String, Object?>{
    'schema': 'sessionly.bench.v1',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'platform':
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'dart_version': Platform.version,
    'results': results.map((r) => r.toJson()).toList(),
  };
  final json = const JsonEncoder.withIndent('  ').convert(payload);
  if (jsonOut != null) {
    File(jsonOut).writeAsStringSync(json);
    stdout.writeln('\nWrote JSON to $jsonOut');
  }
  stdout
    ..writeln('\n--- JSON ---')
    ..writeln(json);
}

// --- options ----------------------------------------------------------------

class _Opts {
  _Opts({
    required this.repeats,
    required this.iterations,
    required this.jsonOut,
  });

  factory _Opts.parse(List<String> args) {
    var repeats = 3;
    var iterations = 100000;
    String? jsonOut;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String next() => (++i < args.length) ? args[i] : '';
      switch (arg) {
        case '--repeats':
          repeats = int.tryParse(next()) ?? repeats;
        case '--iterations':
          iterations = int.tryParse(next()) ?? iterations;
        case '--json-out':
          jsonOut = next();
      }
    }
    return _Opts(
      repeats: max(1, repeats),
      iterations: max(1000, iterations),
      jsonOut: jsonOut,
    );
  }

  final int repeats;
  final int iterations;
  final String? jsonOut;
}
