import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

void main() {
  group('formatIsoDateTimeMs', () {
    test('emits exactly millisecond precision with a Z suffix', () {
      final instant = DateTime.utc(2026, 7, 18, 10, 30, 59, 821);
      expect(formatIsoDateTimeMs(instant), '2026-07-18T10:30:59.821Z');
    });

    test('truncates sub-millisecond precision', () {
      final instant = DateTime.utc(2026, 7, 18, 10, 30, 59, 821, 456);
      expect(formatIsoDateTimeMs(instant), '2026-07-18T10:30:59.821Z');
    });

    test('pads millisecond and time components', () {
      final instant = DateTime.utc(2026, 1, 2, 3, 4, 5, 7);
      expect(formatIsoDateTimeMs(instant), '2026-01-02T03:04:05.007Z');
    });

    test('converts non-UTC instants to UTC', () {
      final local = DateTime.utc(2026, 7, 18, 10, 30, 59, 821).toLocal();
      expect(formatIsoDateTimeMs(local), '2026-07-18T10:30:59.821Z');
    });
  });

  group('parseIsoDateTimeMs', () {
    test('round-trips the canonical wire shape', () {
      const wire = '2026-07-18T10:30:59.821Z';
      final parsed = parseIsoDateTimeMs(wire, 'ts');
      expect(parsed.isUtc, isTrue);
      expect(formatIsoDateTimeMs(parsed), wire);
    });

    test('rejects a missing millisecond fraction', () {
      expect(
        () => parseIsoDateTimeMs('2026-07-18T10:30:59Z', 'ts'),
        throwsA(isA<SessionlyProtocolError>()),
      );
    });

    test('rejects a non-Z offset', () {
      expect(
        () => parseIsoDateTimeMs('2026-07-18T10:30:59.821+05:30', 'ts'),
        throwsA(isA<SessionlyProtocolError>()),
      );
    });

    test('rejects microsecond precision', () {
      expect(
        () => parseIsoDateTimeMs('2026-07-18T10:30:59.821456Z', 'ts'),
        throwsA(isA<SessionlyProtocolError>()),
      );
    });
  });
}
