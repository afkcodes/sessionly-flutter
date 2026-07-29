import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

void main() {
  const timeoutMs = 30 * 60 * 1000;

  Sessionizer makeSessionizer(KvStore kv) => Sessionizer(
    kv: kv,
    uuid: UuidV7Generator(random: Random(7), nowMs: () => 1000),
    timeoutMs: timeoutMs,
  );

  group('Sessionizer', () {
    test('cold start synthesizes first_open then session_start', () async {
      final kv = InMemoryKvStore();
      final s = makeSessionizer(kv);
      await s.load();
      final touch = await s.touch(1000);
      expect(touch.synthetic.map((p) => p.name), [
        'first_open',
        'session_start',
      ]);
      expect(touch.sessionId, isNotNull);
      // Both synthesized events belong to the new session.
      expect(
        touch.synthetic.every((p) => p.sessionId == touch.sessionId),
        isTrue,
      );
    });

    test('activity within the window keeps the same session', () async {
      final s = makeSessionizer(InMemoryKvStore());
      await s.load();
      final first = await s.touch(1000);
      final second = await s.touch(1000 + timeoutMs); // exactly at boundary
      expect(second.synthetic, isEmpty);
      expect(second.sessionId, first.sessionId);
    });

    test(
      'inactivity past the window rotates with a timeout session_end',
      () async {
        final s = makeSessionizer(InMemoryKvStore());
        await s.load();
        final first = await s.touch(1000);
        final rotated = await s.touch(1000 + timeoutMs + 1);
        expect(rotated.synthetic.map((p) => p.name), [
          'session_end',
          'session_start',
        ]);
        final end = rotated.synthetic.first;
        expect(end.sessionId, first.sessionId);
        expect(end.props['end_reason'], 'timeout');
        expect(rotated.sessionId, isNot(first.sessionId));
        // first_open is not re-emitted on later sessions.
        expect(rotated.synthetic.any((p) => p.name == 'first_open'), isFalse);
      },
    );

    test(
      'endSession emits a reasoned session_end and cold-starts next',
      () async {
        final s = makeSessionizer(InMemoryKvStore());
        await s.load();
        final open = await s.touch(1000);
        final end = await s.endSession(2000, 'app_exit');
        expect(end, isNotNull);
        expect(end!.name, 'session_end');
        expect(end.sessionId, open.sessionId);
        expect(end.props['end_reason'], 'app_exit');
        // Next activity starts a fresh session (no first_open again).
        final next = await s.touch(3000);
        expect(next.synthetic.map((p) => p.name), ['session_start']);
        expect(next.sessionId, isNot(open.sessionId));
      },
    );

    test('session state persists across a reload', () async {
      final kv = InMemoryKvStore();
      final s1 = makeSessionizer(kv);
      await s1.load();
      final first = await s1.touch(1000);

      final s2 = makeSessionizer(kv);
      await s2.load();
      final resumed = await s2.touch(1000 + 60 * 1000);
      expect(resumed.synthetic, isEmpty);
      expect(resumed.sessionId, first.sessionId);
    });
  });
}
