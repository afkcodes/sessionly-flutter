/// Sqlite-backed [QueueStore] + [KvStore] (docs/03 chose `sqlite3`, pure FFI,
/// so it runs in a plain Dart isolate). WAL mode for crash safety; one db file
/// holds the event queue and the kv table. Synchronous FFI is fine here — it
/// only ever runs in the background isolate, never on the main thread
/// (Rule 0.2).
library;

import 'dart:convert';

import 'package:sessionly_flutter/src/engine/worker/kv_store.dart';
import 'package:sessionly_flutter/src/engine/worker/queue_store.dart';
import 'package:sqlite3/sqlite3.dart';

/// Opens (and migrates) the engine's sqlite db, exposing a [QueueStore] and a
/// companion [KvStore] over the same connection.
class SqliteStore implements QueueStore {
  SqliteStore._(this._db, this.maxBytes);

  /// Opens the db at [path] (created if absent) with WAL mode, capped at
  /// [maxBytes]. Pending rows from a previous run survive and are re-read.
  factory SqliteStore.open(String path, {required int maxBytes}) {
    final db = sqlite3.open(path)
      ..execute('PRAGMA journal_mode=WAL;')
      ..execute('PRAGMA synchronous=NORMAL;')
      ..execute(
        'CREATE TABLE IF NOT EXISTS queue '
        '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'created_ms INTEGER, bytes BLOB);',
      )
      ..execute('CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY, v TEXT);');
    return SqliteStore._(db, maxBytes);
  }

  final Database _db;

  /// Byte ceiling before oldest-first eviction.
  final int maxBytes;

  /// Key-value view over the same connection (identity, session, config).
  late final KvStore kv = _SqliteKvStore(_db);

  @override
  Future<int> enqueue(List<String> jsons, {required int nowMs}) async {
    if (jsons.isEmpty) return 0;
    final insert = _db.prepare(
      'INSERT INTO queue(created_ms, bytes) VALUES (?, ?);',
    );
    _db.execute('BEGIN;');
    try {
      for (final json in jsons) {
        insert.execute([nowMs, utf8.encode(json)]);
      }
      _db.execute('COMMIT;');
    } on Object {
      _db.execute('ROLLBACK;');
      rethrow;
    } finally {
      insert.close();
    }
    return _evict();
  }

  int _evict() {
    var evicted = 0;
    while (_countSync() > 1 && _bytesSync() > maxBytes) {
      _db.execute(
        'DELETE FROM queue WHERE id = '
        '(SELECT id FROM queue ORDER BY id ASC LIMIT 1);',
      );
      evicted++;
    }
    return evicted;
  }

  @override
  Future<List<QueueRow>> peek(int limit) async {
    final rows = _db.select(
      'SELECT id, bytes FROM queue ORDER BY id ASC LIMIT ?;',
      [limit],
    );
    return rows
        .map(
          (r) => QueueRow(
            id: r['id'] as int,
            json: utf8.decode(r['bytes'] as List<int>),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> ack(List<int> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    _db.execute('BEGIN;');
    try {
      _db
        ..execute('DELETE FROM queue WHERE id IN ($placeholders);', ids)
        ..execute('COMMIT;');
    } on Object {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  Future<int> count() async => _countSync();

  @override
  Future<int> totalBytes() async => _bytesSync();

  int _countSync() =>
      _db.select('SELECT COUNT(*) AS n FROM queue;').first['n'] as int;

  int _bytesSync() =>
      _db
              .select('SELECT COALESCE(SUM(LENGTH(bytes)), 0) AS b FROM queue;')
              .first['b']
          as int;

  @override
  Future<void> close() async => _db.close();
}

class _SqliteKvStore implements KvStore {
  _SqliteKvStore(this._db);

  final Database _db;

  @override
  Future<String?> get(String key) async {
    final rows = _db.select('SELECT v FROM kv WHERE k = ?;', [key]);
    return rows.isEmpty ? null : rows.first['v'] as String?;
  }

  @override
  Future<void> set(String key, String value) async => _db.execute(
    'INSERT OR REPLACE INTO kv(k, v) VALUES (?, ?);',
    [key, value],
  );

  @override
  Future<void> remove(String key) async =>
      _db.execute('DELETE FROM kv WHERE k = ?;', [key]);

  @override
  Future<void> close() async {}
}
