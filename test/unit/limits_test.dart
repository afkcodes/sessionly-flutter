import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

void main() {
  group('validateProps', () {
    test('accepts scalars, arrays and a single-level nested object', () {
      final result = validateProps({
        'str': 'a',
        'num': 1,
        'dbl': 4.2,
        'flag': true,
        'nul': null,
        'list': [1, 2, 3],
        'meta': {'region': 'apac', 'tier': 2},
      });
      expect(result.isValid, isTrue);
      expect(result.reason, isNull);
    });

    test('rejects nesting deeper than two levels', () {
      final result = validateProps({
        'meta': {
          'nested': {'deep': 1},
        },
      });
      expect(result.isValid, isFalse);
    });

    test('accepts exactly the max key count', () {
      final props = {for (var i = 0; i < propsMaxKeys; i++) 'k$i': i};
      expect(validateProps(props).isValid, isTrue);
    });

    test('rejects more than the max key count', () {
      final props = {for (var i = 0; i < propsMaxKeys + 1; i++) 'k$i': i};
      final result = validateProps(props);
      expect(result.isValid, isFalse);
      expect(result.reason, contains('keys'));
    });

    test('rejects serialized payloads over the byte cap', () {
      final result = validateProps({'blob': 'x' * (propsMaxBytes + 1)});
      expect(result.isValid, isFalse);
      expect(result.reason, contains('size'));
    });

    test('accepts a payload just under the byte cap', () {
      final result = validateProps({'blob': 'x' * (propsMaxBytes - 32)});
      expect(result.isValid, isTrue);
    });
  });
}
