/// Latency-sample statistics + budget checks for the micro-benchmark harness.
/// Pure Dart (no Flutter) so the harness runs under `dart run` on any runner.
library;

/// Percentile/summary statistics over a set of millisecond latency samples.
class Stats {
  /// Computes summary statistics from [samplesMs] (need not be pre-sorted).
  factory Stats.fromSamples(List<double> samplesMs) {
    final sorted = List<double>.of(samplesMs)..sort();
    final n = sorted.length;
    var sum = 0.0;
    for (final s in sorted) {
      sum += s;
    }
    return Stats._(
      count: n,
      meanMs: n == 0 ? 0 : sum / n,
      p50Ms: _percentile(sorted, 0.50),
      p99Ms: _percentile(sorted, 0.99),
      maxMs: n == 0 ? 0 : sorted[n - 1],
    );
  }

  Stats._({
    required this.count,
    required this.meanMs,
    required this.p50Ms,
    required this.p99Ms,
    required this.maxMs,
  });

  /// Number of samples.
  final int count;

  /// Arithmetic mean in milliseconds.
  final double meanMs;

  /// Median (p50) in milliseconds.
  final double p50Ms;

  /// 99th percentile in milliseconds.
  final double p99Ms;

  /// Worst observed sample in milliseconds.
  final double maxMs;

  static double _percentile(List<double> sorted, double q) {
    if (sorted.isEmpty) return 0;
    final rank = (q * (sorted.length - 1)).round();
    return sorted[rank];
  }

  /// The JSON view of these statistics.
  Map<String, Object?> toJson() => {
    'count': count,
    'mean_ms': meanMs,
    'p50_ms': p50Ms,
    'p99_ms': p99Ms,
    'max_ms': maxMs,
  };
}

/// A single named benchmark result plus its pass/fail budget verdict.
class BenchResult {
  /// Creates a result. [budgetMs] and [budgetMetric] are null for informational
  /// benchmarks that report numbers but never fail the gate.
  BenchResult({
    required this.name,
    required this.stats,
    this.budgetMs,
    this.budgetMetric,
    this.note,
    this.extra = const {},
  });

  /// Human/machine benchmark id, e.g. `capture_gate.enqueue`.
  final String name;

  /// The measured latency statistics.
  final Stats stats;

  /// Budget ceiling in ms, or null when informational.
  final double? budgetMs;

  /// Which statistic the budget applies to (`p99`, `mean`, ...).
  final String? budgetMetric;

  /// Optional human note (units, method).
  final String? note;

  /// Extra machine-readable fields (throughput, etc.).
  final Map<String, Object?> extra;

  /// The measured value the budget is checked against.
  double? get measured => switch (budgetMetric) {
    'p99' => stats.p99Ms,
    'p50' => stats.p50Ms,
    'mean' => stats.meanMs,
    'max' => stats.maxMs,
    _ => null,
  };

  /// `true` when informational or within budget.
  bool get passed {
    final m = measured;
    final b = budgetMs;
    if (m == null || b == null) return true;
    return m <= b;
  }

  /// `true` when this result carries an enforced budget.
  bool get enforced => budgetMs != null && budgetMetric != null;

  /// The JSON view of this result.
  Map<String, Object?> toJson() => {
    'name': name,
    'stats': stats.toJson(),
    if (budgetMs != null) 'budget_ms': budgetMs,
    if (budgetMetric != null) 'budget_metric': budgetMetric,
    if (note != null) 'note': note,
    'passed': passed,
    ...extra,
  };
}

/// Formats a millisecond value with microsecond-friendly precision.
String fmtMs(double ms) {
  if (ms >= 1) return '${ms.toStringAsFixed(3)} ms';
  return '${(ms * 1000).toStringAsFixed(2)} µs';
}
