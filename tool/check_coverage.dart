/// Dependency-free line-coverage gate for the Flutter SDK.
///
/// Parses the `coverage/lcov.info` produced by `flutter test --coverage`,
/// sums `LF`/`LH` across every record, and fails (exit 1) when the ratio is
/// below the threshold given as the first argument (percent, e.g. `85`).
///
/// We parse lcov ourselves rather than shelling out to `lcov`/`genhtml`
/// because those binaries are not present on the CI runner (or on dev
/// machines); the format is line-oriented and trivial to total.
///
/// The floor is intentionally below the TS core packages' ≥90% (Rule 5.3):
/// `default_platform.dart` is a MethodChannel shim exercised only on a real
/// device, `main_thread_watchdog.dart` is wall-clock ANR detection, and the
/// engine runs in a spawned isolate whose executed lines the main-isolate
/// coverage collector under-counts. The threshold reflects that reality and
/// still catches a real regression in the host-testable surface.
library;

import 'dart:io';

void main(List<String> args) {
  final threshold = args.isEmpty ? 85.0 : double.parse(args.first);
  final file = File('coverage/lcov.info');
  if (!file.existsSync()) {
    stderr.writeln(
      'check_coverage: coverage/lcov.info not found — run '
      '`flutter test --coverage` first.',
    );
    exit(2);
  }

  var totalFound = 0;
  var totalHit = 0;
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('LF:')) {
      totalFound += int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      totalHit += int.parse(line.substring(3));
    }
  }

  if (totalFound == 0) {
    stderr.writeln('check_coverage: no instrumented lines found.');
    exit(2);
  }

  final pct = totalHit / totalFound * 100;
  final rounded = pct.toStringAsFixed(2);
  if (pct + 1e-9 < threshold) {
    stderr.writeln(
      'check_coverage: FAIL — line coverage $rounded% '
      '($totalHit/$totalFound) is below the ${threshold.toStringAsFixed(0)}% '
      'floor.',
    );
    exit(1);
  }
  stdout.writeln(
    'check_coverage: OK — line coverage $rounded% '
    '($totalHit/$totalFound) ≥ ${threshold.toStringAsFixed(0)}% floor.',
  );
}
