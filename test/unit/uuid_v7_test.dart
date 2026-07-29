import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

void main() {
  group('UuidV7Generator', () {
    test('generates canonical, valid UUIDv7 strings', () {
      final gen = UuidV7Generator(
        random: Random(1),
        nowMs: () => 1721298659821,
      );
      for (var i = 0; i < 100; i++) {
        final id = gen.generate();
        expect(isUuidV7(id), isTrue, reason: '$id must be a valid UUIDv7');
        expect(id.length, 36);
        // Version nibble (index 14) is '7'; variant nibble (index 19) in 8..b.
        expect(id[14], '7');
        expect('89ab'.contains(id[19]), isTrue);
      }
    });

    test('encodes the millisecond timestamp in the leading 48 bits', () {
      const ms = 1721298659821;
      final gen = UuidV7Generator(random: Random(7), nowMs: () => ms);
      final id = gen.generate();
      final prefix = id.replaceAll('-', '').substring(0, 12);
      expect(prefix, ms.toRadixString(16).padLeft(12, '0'));
    });

    test('later timestamps sort lexicographically after earlier ones', () {
      final random = Random(42);
      var clock = 1000000000000;
      final gen = UuidV7Generator(random: random, nowMs: () => clock);
      final ids = <String>[];
      for (var i = 0; i < 50; i++) {
        ids.add(gen.generate());
        clock += 1;
      }
      final sorted = [...ids]..sort();
      expect(ids, sorted, reason: 'monotonic clock must yield sorted ids');
    });

    test('generateUuidV7 convenience produces valid ids', () {
      expect(isUuidV7(generateUuidV7()), isTrue);
    });
  });

  group('isUuidV7', () {
    test('accepts a v7 id', () {
      expect(isUuidV7('0190a1b2-c3d4-7e5f-8a0b-000000000001'), isTrue);
    });

    test('rejects a v4 id (wrong version nibble)', () {
      expect(isUuidV7('0190a1b2-c3d4-4e5f-8a0b-000000000001'), isFalse);
    });

    test('rejects malformed strings', () {
      expect(isUuidV7('not-a-uuid'), isFalse);
      expect(isUuidV7(''), isFalse);
      expect(isUuidV7('0190a1b2c3d47e5f8a0b000000000001'), isFalse);
    });
  });
}
