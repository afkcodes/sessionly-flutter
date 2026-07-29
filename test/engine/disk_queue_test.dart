import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

bool _sqliteAvailable() {
  try {
    SqliteStore.open(':memory:', maxBytes: 1024);
    return true;
  } on Object {
    return false;
  }
}

void main() {
  group('InMemoryQueueStore (interface contract)', () {
    test('enqueue, peek oldest-first, ack deletes', () async {
      final q = InMemoryQueueStore(maxBytes: 1 << 20);
      await q.enqueue(['a', 'b', 'c'], nowMs: 1);
      expect(await q.count(), 3);
      final rows = await q.peek(2);
      expect(rows.map((r) => r.json), ['a', 'b']);
      await q.ack(rows.map((r) => r.id).toList());
      expect(await q.count(), 1);
      expect((await q.peek(10)).single.json, 'c');
    });

    test('evicts oldest when over the byte cap', () async {
      final q = InMemoryQueueStore(maxBytes: 10);
      final evicted = await q.enqueue(['xxxxx', 'yyyyy', 'zzzzz'], nowMs: 1);
      expect(evicted, greaterThan(0));
      expect(await q.totalBytes(), lessThanOrEqualTo(10));
    });
  });

  group('SqliteStore', () {
    if (!_sqliteAvailable()) {
      test('skipped — native libsqlite3 unavailable', () {}, skip: true);
      return;
    }

    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('sly_queue_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    String dbPath() => '${dir.path}/sessionly.db';

    test('enqueue/peek/ack round-trip', () async {
      final store = SqliteStore.open(dbPath(), maxBytes: 1 << 20);
      await store.enqueue(['e1', 'e2'], nowMs: 100);
      expect(await store.count(), 2);
      final rows = await store.peek(10);
      expect(rows.map((r) => r.json), ['e1', 'e2']);
      await store.ack([rows.first.id]);
      expect(await store.count(), 1);
      await store.close();
    });

    test('caps total bytes with oldest-first eviction', () async {
      final store = SqliteStore.open(dbPath(), maxBytes: 20);
      final evicted = await store.enqueue([
        'aaaaaaaa',
        'bbbbbbbb',
        'cccccccc',
      ], nowMs: 1);
      expect(evicted, greaterThan(0));
      expect(await store.totalBytes(), lessThanOrEqualTo(20));
      await store.close();
    });

    test('pending rows survive a reopen (crash-safety)', () async {
      final first = SqliteStore.open(dbPath(), maxBytes: 1 << 20);
      await first.enqueue(['survive_me'], nowMs: 1);
      await first.close(); // simulate process death after a clean write

      final reopened = SqliteStore.open(dbPath(), maxBytes: 1 << 20);
      final rows = await reopened.peek(10);
      expect(rows.single.json, 'survive_me');
      await reopened.close();
    });

    test('kv view stores and clears keys', () async {
      final store = SqliteStore.open(dbPath(), maxBytes: 1 << 20);
      await store.kv.set('anonymous_id', 'anon_abc');
      expect(await store.kv.get('anonymous_id'), 'anon_abc');
      await store.kv.remove('anonymous_id');
      expect(await store.kv.get('anonymous_id'), isNull);
      await store.close();
    });
  });
}
