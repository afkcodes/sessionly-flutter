/// RFC 9562 UUIDv7 generation and validation.
library;

import 'dart:math';
import 'dart:typed_data';

export 'package:sessionly_flutter/src/protocol/formats.dart' show isUuidV7;

/// Generates RFC 9562 UUIDv7 identifiers: a 48-bit Unix-millisecond timestamp
/// prefix followed by random bits, so ids are time-ordered and globally unique.
///
/// Time-ordering is what makes ingestion idempotent and cheap to sort
/// (Rule 2.4). The generator is seedable (inject `random` and `nowMs`) so tests
/// are deterministic; the default constructor uses a fresh `Random` and the
/// system clock.
class UuidV7Generator {
  /// Creates a generator. Inject [random] and [nowMs] for deterministic output
  /// in tests; both default to non-deterministic system sources.
  UuidV7Generator({Random? random, int Function()? nowMs})
    : _random = random ?? Random(),
      _nowMs = nowMs ?? _systemNowMs;

  static int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

  final Random _random;
  final int Function() _nowMs;

  static const String _hex = '0123456789abcdef';

  /// Returns a fresh UUIDv7 string in canonical 8-4-4-4-12 form.
  String generate() {
    final ms = _nowMs();
    final bytes = Uint8List(16)
      // 48-bit big-endian Unix-millisecond timestamp.
      ..[0] = (ms >> 40) & 0xff
      ..[1] = (ms >> 32) & 0xff
      ..[2] = (ms >> 24) & 0xff
      ..[3] = (ms >> 16) & 0xff
      ..[4] = (ms >> 8) & 0xff
      ..[5] = ms & 0xff
      // Version nibble 7 in the high nibble of byte 6, rand_a in the rest.
      ..[6] = 0x70 | _random.nextInt(0x10)
      ..[7] = _random.nextInt(0x100)
      // Variant bits (10) in the top two bits of byte 8, rand_b in the rest.
      ..[8] = 0x80 | _random.nextInt(0x40);
    for (var i = 9; i < 16; i++) {
      bytes[i] = _random.nextInt(0x100);
    }
    return _format(bytes);
  }

  String _format(Uint8List bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) buffer.write('-');
      final byte = bytes[i];
      buffer
        ..write(_hex[(byte >> 4) & 0x0f])
        ..write(_hex[byte & 0x0f]);
    }
    return buffer.toString();
  }
}

/// A process-wide default generator using the system clock and a secure-enough
/// PRNG. Prefer an injected [UuidV7Generator] where determinism matters.
final UuidV7Generator defaultUuidV7Generator = UuidV7Generator(
  random: Random.secure(),
);

/// Convenience: a fresh UUIDv7 from [defaultUuidV7Generator].
String generateUuidV7() => defaultUuidV7Generator.generate();
