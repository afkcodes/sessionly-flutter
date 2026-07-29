// Facade-level feature-flag reads (docs/06 § in-app flag channel) with an
// injected FlagAware host — no isolate. Asserts: delivered enabled/value
// passthrough, default-off for an absent key, and default-off (no host read)
// when the master switch is off. The full delivery + exposure path is covered
// end-to-end in isolate_host_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

/// A host that also carries a fixed flag map (like the real IsolateEngineHost).
class FlagRecordingHost implements EngineHost, FlagAware {
  FlagRecordingHost(this._flags);

  final Map<String, Object?> _flags;
  final List<List<Map<String, Object?>>> batches = [];

  @override
  Map<String, Object?> get flags => _flags;

  @override
  void submit(List<Map<String, Object?>> records) => batches.add(records);

  @override
  Future<void> flush() async {}

  @override
  Future<void> shutdown() async {}
}

SessionlyConfig config({bool enabled = true}) => SessionlyConfig(
  writeKey: 'sly_w_test',
  endpoint: Uri.parse('https://fp.example.com'),
  enabled: enabled,
);

void main() {
  tearDown(Sessionly.shutdown);

  test('reads the delivered enabled state and structured value', () async {
    await Sessionly.init(
      config(),
      host: FlagRecordingHost({
        'new_checkout': {'enabled': true, 'value': 'variant_b'},
        'beta': {'enabled': false},
      }),
      installAutoCapture: false,
      drainInterval: const Duration(days: 1),
    );

    final flag = Sessionly.flag('new_checkout');
    expect(flag.enabled, isTrue);
    expect(flag.value, 'variant_b');
    expect(Sessionly.isEnabled('new_checkout'), isTrue);
    expect(Sessionly.isEnabled('beta'), isFalse);
  });

  test('an absent key resolves default-off', () async {
    await Sessionly.init(
      config(),
      host: FlagRecordingHost(const {}),
      installAutoCapture: false,
      drainInterval: const Duration(days: 1),
    );
    final flag = Sessionly.flag('missing');
    expect(flag.enabled, isFalse);
    expect(flag.value, isNull);
    expect(Sessionly.isEnabled('missing'), isFalse);
  });

  test('a disabled SDK reads default-off and never throws', () async {
    await Sessionly.init(
      config(enabled: false),
      host: FlagRecordingHost({
        'x': {'enabled': true},
      }),
      installAutoCapture: false,
      drainInterval: const Duration(days: 1),
    );
    // Master kill switch: no host is even wired, so every flag is off.
    expect(Sessionly.isEnabled('x'), isFalse);
    expect(() => Sessionly.flag('x'), returnsNormally);
  });
}
