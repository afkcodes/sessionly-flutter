import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

class RecordingHost implements EngineHost {
  final List<List<Map<String, Object?>>> batches = [];
  int flushes = 0;

  @override
  void submit(List<Map<String, Object?>> records) => batches.add(records);

  @override
  Future<void> flush() async => flushes++;

  @override
  Future<void> shutdown() async {}
}

class ThrowingHost implements EngineHost {
  @override
  void submit(List<Map<String, Object?>> records) =>
      throw StateError('engine down');

  @override
  Future<void> flush() async => throw StateError('engine down');

  @override
  Future<void> shutdown() async {}
}

class ThrowingUuid extends UuidV7Generator {
  ThrowingUuid() : super(random: Random(0));

  @override
  String generate() => throw StateError('no ids');
}

SessionlyConfig config() => SessionlyConfig(
  writeKey: 'sly_w_test',
  endpoint: Uri.parse('https://fp.example.com'),
);

void main() {
  tearDown(Sessionly.shutdown);

  group('Sessionly facade (no-throw guarantee, Rule 0.3)', () {
    test('track never propagates when the id generator throws', () async {
      await Sessionly.init(
        config(),
        host: RecordingHost(),
        uuid: ThrowingUuid(),
        drainInterval: const Duration(days: 1),
      );
      expect(() => Sessionly.track('boom'), returnsNormally);
      expect(Sessionly.debugInternalErrorCount, greaterThan(0));
    });

    test('flush never propagates when the engine host throws', () async {
      await Sessionly.init(
        config(),
        host: ThrowingHost(),
        drainInterval: const Duration(days: 1),
      );
      await expectLater(Sessionly.flush(), completes);
      expect(Sessionly.debugInternalErrorCount, greaterThan(0));
    });

    test('every public entry is safe before init completes', () {
      // No init called: calls must be inert, not throwing.
      expect(() {
        Sessionly.track('a');
        Sessionly.screen('Home');
        Sessionly.identify('u1');
        Sessionly.reset();
      }, returnsNormally);
    });
  });

  group('Sessionly facade lifecycle', () {
    test('init is idempotent — a second init is ignored', () async {
      final host1 = RecordingHost();
      final host2 = RecordingHost();
      await Sessionly.init(
        config(),
        host: host1,
        drainInterval: const Duration(days: 1),
      );
      await Sessionly.init(
        config(),
        host: host2,
        drainInterval: const Duration(days: 1),
      );
      Sessionly.track('checkout');
      await Sessionly.flush();
      expect(host1.batches, isNotEmpty);
      expect(host2.batches, isEmpty);
    });

    test('flush drains buffered captures to the host', () async {
      final host = RecordingHost();
      await Sessionly.init(
        config(),
        host: host,
        drainInterval: const Duration(days: 1),
      );
      Sessionly.track('a');
      Sessionly.track('b');
      await Sessionly.flush();
      final all = host.batches.expand((b) => b).toList();
      expect(
        all.where((r) => r[RecordKey.kind] == RecordKind.event),
        hasLength(2),
      );
      expect(host.flushes, greaterThan(0));
    });
  });
}
