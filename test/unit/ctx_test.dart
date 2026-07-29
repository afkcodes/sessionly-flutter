import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

/// Guards the additive web ctx fields (docs/05): absent-or-value on the wire,
/// omitted from `toJson` when null, explicit `null` rejected (mirrors the TS
/// `.optional()` fields). Fixtures cover the happy paths; this covers edges.
void main() {
  Map<String, Object?> baseCtx() => {
    'app_version': '1.4.0',
    'build': null,
    'os': 'web',
    'os_version': '125.0',
    'device_class': 'high',
    'locale': 'en-US',
    'network': 'wifi',
    'screen_w': 1920,
    'screen_h': 1080,
  };

  test('parses a ctx with none of the additive fields (all null)', () {
    final ctx = EventCtx.fromJson(baseCtx());
    expect(ctx.browser, isNull);
    expect(ctx.viewportW, isNull);
    expect(ctx.connection, isNull);
    // Omitted from the wire shape, not serialized as null.
    expect(ctx.toJson().containsKey('browser'), isFalse);
    expect(ctx.toJson().containsKey('connection'), isFalse);
  });

  test('parses and re-serializes a ctx carrying every additive field', () {
    final json = baseCtx()
      ..addAll({
        'browser': 'chrome',
        'browser_version': '125.0.6422.112',
        'viewport_w': 1440,
        'viewport_h': 900,
        'connection': '4g',
      });
    final ctx = EventCtx.fromJson(json);
    expect(ctx.connection, '4g');
    expect(ctx.toJson(), json);
  });

  test('accepts every documented connection wire value', () {
    for (final value in ConnectionValue.wireValues) {
      final ctx = EventCtx.fromJson(baseCtx()..['connection'] = value);
      expect(ctx.connection, value);
    }
  });

  test('rejects an unknown connection value at ctx.connection', () {
    expect(
      () => EventCtx.fromJson(baseCtx()..['connection'] = '5g'),
      throwsA(
        isA<SessionlyProtocolError>().having(
          (e) => e.path,
          'path',
          'ctx.connection',
        ),
      ),
    );
  });

  test('rejects viewport_w = 0 at ctx.viewport_w', () {
    expect(
      () => EventCtx.fromJson(baseCtx()..['viewport_w'] = 0),
      throwsA(
        isA<SessionlyProtocolError>().having(
          (e) => e.path,
          'path',
          'ctx.viewport_w',
        ),
      ),
    );
  });

  test('rejects an explicit null on an optional field (absent-or-value)', () {
    expect(
      () => EventCtx.fromJson(baseCtx()..['browser'] = null),
      throwsA(
        isA<SessionlyProtocolError>().having(
          (e) => e.path,
          'path',
          'ctx.browser',
        ),
      ),
    );
  });
}
