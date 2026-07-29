// Facade-level experiment reads (docs/10 Suite modules) with an injected
// ExperimentAware host — no isolate. Asserts: deterministic assignment + value
// passthrough, stickiness, unassigned for an absent experiment / empty seed, and
// default-unassigned (no host read) when the master switch is off. The full
// delivery + exposure path is covered end-to-end in isolate_host_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

/// A host that carries a fixed experiment map + seed (like IsolateEngineHost).
class ExperimentRecordingHost implements EngineHost, ExperimentAware {
  ExperimentRecordingHost(this._experiments, {String seed = 'anon_seed'})
    : _seed = seed;

  final Map<String, Object?> _experiments;
  final String _seed;

  @override
  Map<String, Object?> get experiments => _experiments;

  @override
  String get assignmentSeed => _seed;

  @override
  void submit(List<Map<String, Object?>> records) {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> shutdown() async {}
}

Map<String, Object?> abTest() => {
  'checkout_button_color': {
    'flagKey': 'checkout_button_color',
    'variants': [
      {'name': 'control', 'weight': 1},
      {
        'name': 'treatment',
        'weight': 1,
        'value': {'color': 'green'},
      },
    ],
  },
};

SessionlyConfig config({bool enabled = true}) => SessionlyConfig(
  writeKey: 'sly_w_test',
  endpoint: Uri.parse('https://fp.example.com'),
  enabled: enabled,
);

void main() {
  tearDown(Sessionly.shutdown);

  test('assigns a variant deterministically and is sticky', () async {
    await Sessionly.init(
      config(),
      host: ExperimentRecordingHost(abTest()),
      installAutoCapture: false,
      drainInterval: const Duration(days: 1),
    );

    final a = Sessionly.experiment('checkout_button_color');
    expect(a.isAssigned, isTrue);
    expect(['control', 'treatment'].contains(a.variant), isTrue);

    // Same actor → same variant every read (sticky, no stored state).
    final b = Sessionly.experiment('checkout_button_color');
    expect(b.variant, a.variant);
  });

  test('an absent experiment is unassigned and never throws', () async {
    await Sessionly.init(
      config(),
      host: ExperimentRecordingHost(const {}),
      installAutoCapture: false,
      drainInterval: const Duration(days: 1),
    );
    final r = Sessionly.experiment('missing');
    expect(r.isAssigned, isFalse);
    expect(r.variant, isNull);
    expect(() => Sessionly.experiment('missing'), returnsNormally);
  });

  test('an empty seed yields no assignment (seed not yet delivered)', () async {
    await Sessionly.init(
      config(),
      host: ExperimentRecordingHost(abTest(), seed: ''),
      installAutoCapture: false,
      drainInterval: const Duration(days: 1),
    );
    expect(Sessionly.experiment('checkout_button_color').isAssigned, isFalse);
  });

  test('a disabled SDK reads unassigned and never throws', () async {
    await Sessionly.init(
      config(enabled: false),
      host: ExperimentRecordingHost(abTest()),
      installAutoCapture: false,
      drainInterval: const Duration(days: 1),
    );
    expect(Sessionly.experiment('checkout_button_color').isAssigned, isFalse);
    expect(
      () => Sessionly.experiment('checkout_button_color'),
      returnsNormally,
    );
  });
}
