/// The crash-safe disk queue seam. `disk_queue.dart` implements this against
/// sqlite; tests can use [InMemoryQueueStore] so they never need a native lib.
library;

/// A stored, not-yet-acked event row.
class QueueRow {
  /// Creates a [QueueRow].
  const QueueRow({required this.id, required this.json});

  /// Monotonic row id (ack target).
  final int id;

  /// The serialized event wire JSON.
  final String json;
}

/// Append-only, byte-capped, oldest-first-eviction queue of serialized events.
/// All methods are async — Rule 0.2 forbids sync I/O on the main isolate, and
/// the async surface keeps the seam identical across sqlite and fakes.
abstract interface class QueueStore {
  /// Persists [jsons] (transactionally). If the total-byte cap would be
  /// exceeded, evicts oldest rows first. Returns the number evicted so the
  /// caller can bump `dropped_disk`.
  Future<int> enqueue(List<String> jsons, {required int nowMs});

  /// Oldest [limit] rows, id-ascending.
  Future<List<QueueRow>> peek(int limit);

  /// Deletes [ids] (transactional batch ack).
  Future<void> ack(List<int> ids);

  /// Current row count.
  Future<int> count();

  /// Current total stored bytes.
  Future<int> totalBytes();

  /// Releases resources.
  Future<void> close();
}

/// In-memory [QueueStore] for tests and for the fallback when the native sqlite
/// library is unavailable. Enforces the same byte cap and eviction rules.
class InMemoryQueueStore implements QueueStore {
  /// Creates a store capped at [maxBytes].
  InMemoryQueueStore({required this.maxBytes});

  /// Byte ceiling before oldest-first eviction.
  final int maxBytes;

  final List<QueueRow> _rows = [];
  int _bytes = 0;
  int _nextId = 1;

  @override
  Future<int> enqueue(List<String> jsons, {required int nowMs}) async {
    for (final json in jsons) {
      _rows.add(QueueRow(id: _nextId++, json: json));
      _bytes += json.length;
    }
    var evicted = 0;
    while (_rows.length > 1 && _bytes > maxBytes) {
      final row = _rows.removeAt(0);
      _bytes -= row.json.length;
      evicted++;
    }
    return evicted;
  }

  @override
  Future<List<QueueRow>> peek(int limit) async =>
      _rows.take(limit).toList(growable: false);

  @override
  Future<void> ack(List<int> ids) async {
    final drop = ids.toSet();
    _rows.removeWhere((row) {
      if (drop.contains(row.id)) {
        _bytes -= row.json.length;
        return true;
      }
      return false;
    });
  }

  @override
  Future<int> count() async => _rows.length;

  @override
  Future<int> totalBytes() async => _bytes;

  @override
  Future<void> close() async {}
}
