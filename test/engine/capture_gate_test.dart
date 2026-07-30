import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

void main() {
  group('CaptureGate', () {
    late List<Map<String, Object?>> sunk;
    late RingBuffer<Map<String, Object?>> buffer;

    CaptureGate makeGate({int maxEvents = 100}) {
      buffer = RingBuffer<Map<String, Object?>>(
        maxEvents: maxEvents,
        maxBytes: 1 << 20,
      );
      return CaptureGate(
        buffer: buffer,
        sink: sunk.addAll,
        uuid: UuidV7Generator(random: Random(1), nowMs: () => 1000),
        nowMs: () => 1721298659821,
      );
    }

    setUp(() {
      sunk = [];
    });

    test(
      'captureEvent stamps a UUIDv7 event_id and ts, and enqueues '
      'without serializing',
      () {
        final props = {'value': 499};
        makeGate()
          ..captureEvent(type: 'custom', name: 'checkout', props: props)
          ..drainNow();

        expect(sunk, hasLength(1));
        final record = sunk.single;
        expect(record[RecordKey.kind], RecordKind.event);
        expect(isUuidV7(record[RecordKey.eventId]! as String), isTrue);
        expect(record[RecordKey.tsMs], 1721298659821);
        expect(record[RecordKey.name], 'checkout');
        // No serialization on the capture path: the very same props Map
        // instance is carried through, not a JSON string or a copy.
        expect(identical(record[RecordKey.props], props), isTrue);
      },
    );

    test('captureIdentify and captureReset produce typed records', () {
      makeGate()
        ..captureIdentify('user_1')
        ..captureReset()
        ..drainNow();
      expect(sunk.map((r) => r[RecordKey.kind]), [
        RecordKind.identify,
        RecordKind.reset,
      ]);
      expect(sunk.first[RecordKey.userId], 'user_1');
    });

    test('drainNow prefixes a meta record carrying the drop delta', () {
      final gate = makeGate(maxEvents: 2);
      for (var i = 0; i < 5; i++) {
        gate.captureEvent(type: 'custom', name: 'e$i', props: const {});
      }
      gate.drainNow();
      expect(sunk.first[RecordKey.kind], RecordKind.meta);
      expect(sunk.first[RecordKey.droppedBuffer], 3);
      // 2 survivors follow the meta record.
      expect(
        sunk.where((r) => r[RecordKey.kind] == RecordKind.event),
        hasLength(2),
      );
    });

    test('drainNow on an empty buffer does not call the sink', () {
      makeGate().drainNow();
      expect(sunk, isEmpty);
    });
  });

  group('CaptureGate screen_view dedup', () {
    late List<Map<String, Object?>> sunk;
    late int clock;
    late CaptureGate gate;

    // Local functions (not `gate.method`) so a call sequence needs no cascade.
    void view(String screen, {Map<String, Object?> props = const {}}) =>
        gate.captureEvent(
          type: 'auto',
          name: 'screen_view',
          props: props,
          screen: screen,
        );
    void emit(String name, {String? screen}) => gate.captureEvent(
      type: 'auto',
      name: name,
      props: const {},
      screen: screen,
    );

    List<Map<String, Object?>> events() =>
        sunk.where((r) => r[RecordKey.kind] == RecordKind.event).toList();

    setUp(() {
      sunk = [];
      clock = 1000;
      gate = CaptureGate(
        buffer: RingBuffer<Map<String, Object?>>(
          maxEvents: 100,
          maxBytes: 1 << 20,
        ),
        sink: sunk.addAll,
        uuid: UuidV7Generator(random: Random(1), nowMs: () => 1000),
        nowMs: () => clock,
      );
    });

    test(
      'coalesces a same-screen screen_view within the window (keep-first)',
      () {
        // Observer + a manual Sessionly.screen(), ~1 frame apart, one nav.
        view('/circle');
        clock += 25;
        view('/circle', props: const {'nav_type': 'push'});
        gate.drainNow();

        expect(events(), hasLength(1));
        expect(gate.dedupedTotal, 1);
        // Keep-first: the earlier (empty-props) event is the one admitted.
        expect(events().single[RecordKey.props], const <String, Object?>{});
      },
    );

    test('keeps distinct screens and same-screen views past the window', () {
      view('/circle');
      clock += 25;
      view('/learn');
      clock += 800; // past the 700ms default window
      view('/learn');
      gate.drainNow();

      expect(events(), hasLength(3));
      expect(gate.dedupedTotal, 0);
    });

    test('never dedups non-screen_view events or null screens', () {
      emit('tap', screen: '/circle');
      emit('tap', screen: '/circle');
      emit('screen_view');
      emit('screen_view');
      gate.drainNow();

      expect(events(), hasLength(4));
      expect(gate.dedupedTotal, 0);
    });
  });
}
