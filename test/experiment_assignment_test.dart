// The pure deterministic assignment mapping (docs/10 Suite modules). Asserts:
// stability (same seed+key+variants → same variant), weight proportionality
// over many seeds, malformed/empty variant sets degrade to null (never throw),
// and value passthrough.
import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/src/experiment_assignment.dart';

List<Object?> variants(List<(String, int)> pairs) => [
  for (final (name, weight) in pairs) {'name': name, 'weight': weight},
];

void main() {
  test('same seed + key + variants always resolves to the same variant', () {
    final vs = variants([('control', 1), ('treatment', 1)]);
    final a = assignExperimentVariant('anon_abc', 'exp', vs);
    final b = assignExperimentVariant('anon_abc', 'exp', vs);
    expect(a, isNotNull);
    expect(a!.name, b!.name);
  });

  test(
    'different keys can resolve to different variants (independent hash)',
    () {
      final vs = variants([('a', 1), ('b', 1)]);
      // Over several keys we expect both variants to appear for a fixed seed.
      final seen = <String>{};
      for (var i = 0; i < 50; i++) {
        final r = assignExperimentVariant('seed', 'exp_$i', vs);
        if (r != null) seen.add(r.name);
      }
      expect(seen, containsAll(<String>['a', 'b']));
    },
  );

  test('weights bias the distribution proportionally', () {
    final vs = variants([('rare', 1), ('common', 9)]);
    var common = 0;
    const n = 4000;
    for (var i = 0; i < n; i++) {
      final r = assignExperimentVariant('actor_$i', 'exp', vs);
      if (r!.name == 'common') common++;
    }
    final ratio = common / n;
    // 90% weight — allow a generous band for the finite sample.
    expect(ratio, greaterThan(0.82));
    expect(ratio, lessThan(0.97));
  });

  test('an empty variant set yields null (no assignment)', () {
    expect(assignExperimentVariant('seed', 'exp', const []), isNull);
  });

  test('malformed variants are skipped; all-bad yields null', () {
    final bad = <Object?>[
      'not a map',
      {'name': '', 'weight': 5},
      {'name': 'x', 'weight': 0},
      {'name': 'y', 'weight': -3},
      {'weight': 2},
    ];
    expect(assignExperimentVariant('seed', 'exp', bad), isNull);
  });

  test('carries the variant value through', () {
    final vs = <Object?>[
      {
        'name': 'only',
        'weight': 1,
        'value': {'color': 'green'},
      },
    ];
    final r = assignExperimentVariant('seed', 'exp', vs);
    expect(r!.name, 'only');
    expect(r.value, {'color': 'green'});
  });
}
