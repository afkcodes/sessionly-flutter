import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

void main() {
  group('RingBuffer', () {
    test('adds and drains oldest-first, tracking bytes', () {
      final buffer = RingBuffer<int>(maxEvents: 10, maxBytes: 1000)
        ..add(1, 10)
        ..add(2, 20)
        ..add(3, 30);
      expect(buffer.length, 3);
      expect(buffer.bytes, 60);
      expect(buffer.drain(), [1, 2, 3]);
      expect(buffer.bytes, 0);
      expect(buffer.isEmpty, isTrue);
    });

    test('drops oldest on count overflow and counts drops', () {
      final buffer = RingBuffer<int>(maxEvents: 3, maxBytes: 100000);
      for (var i = 0; i < 5; i++) {
        buffer.add(i, 1);
      }
      expect(buffer.length, 3);
      expect(buffer.droppedTotal, 2);
      // Oldest (0, 1) evicted; newest survive.
      expect(buffer.drain(), [2, 3, 4]);
    });

    test('drops oldest on byte overflow', () {
      final buffer = RingBuffer<int>(maxEvents: 1000, maxBytes: 100)
        ..add(1, 60)
        ..add(2, 60); // evicts item 1 (60 + 60 > 100)
      expect(buffer.length, 1);
      expect(buffer.droppedTotal, 1);
      expect(buffer.bytes, 60);
      expect(buffer.drain(), [2]);
    });

    test('drops an item that alone exceeds the byte cap', () {
      final buffer = RingBuffer<int>(maxEvents: 10, maxBytes: 100)..add(1, 500);
      expect(buffer.isEmpty, isTrue);
      expect(buffer.droppedTotal, 1);
    });

    test('takeDroppedDelta returns and resets the delta', () {
      final buffer = RingBuffer<int>(maxEvents: 1, maxBytes: 100000)
        ..add(1, 1)
        ..add(2, 1)
        ..add(3, 1);
      expect(buffer.takeDroppedDelta(), 2);
      expect(buffer.takeDroppedDelta(), 0);
    });

    test('add is O(1) amortized over many operations', () {
      final buffer = RingBuffer<int>(maxEvents: 100, maxBytes: 1 << 30);
      for (var i = 0; i < 100000; i++) {
        buffer.add(i, 8);
      }
      expect(buffer.length, 100);
      expect(buffer.droppedTotal, 100000 - 100);
    });
  });
}
