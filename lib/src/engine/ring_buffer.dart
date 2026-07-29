/// The main-isolate ring buffer: a bounded, drop-oldest queue with O(1) add and
/// drain (Rule 0.1). "Lock-free" here means lock-free by construction — it is
/// pure synchronous single-isolate code, so there is nothing to lock.
library;

import 'dart:collection';

/// A fixed-capacity buffer bounded by both an event count and an approximate
/// byte budget (Rule 0.4). On overflow it evicts the oldest entries and counts
/// them; it never blocks and never grows unbounded.
class RingBuffer<T> {
  /// Creates a buffer capped at [maxEvents] entries and [maxBytes] approximate
  /// bytes. Both caps are enforced on every [add].
  RingBuffer({required this.maxEvents, required this.maxBytes})
    : assert(maxEvents > 0, 'maxEvents must be positive'),
      assert(maxBytes > 0, 'maxBytes must be positive');

  /// Event-count ceiling.
  final int maxEvents;

  /// Approximate-byte ceiling.
  final int maxBytes;

  final Queue<_Slot<T>> _slots = Queue<_Slot<T>>();
  int _bytes = 0;
  int _dropped = 0;

  /// Number of entries currently buffered.
  int get length => _slots.length;

  /// Approximate bytes currently buffered.
  int get bytes => _bytes;

  /// Total entries dropped since construction (drop-oldest overflow).
  int get droppedTotal => _dropped;

  /// `true` when nothing is buffered.
  bool get isEmpty => _slots.isEmpty;

  /// Appends [item] costed at approximately [bytes]. O(1) amortized. If an item
  /// alone exceeds [maxBytes] it is dropped outright; otherwise the oldest
  /// entries are evicted until it fits. Every eviction bumps [droppedTotal].
  void add(T item, int bytes) {
    if (bytes > maxBytes) {
      _dropped++;
      return;
    }
    while (_slots.isNotEmpty &&
        (_slots.length + 1 > maxEvents || _bytes + bytes > maxBytes)) {
      final evicted = _slots.removeFirst();
      _bytes -= evicted.bytes;
      _dropped++;
    }
    _slots.addLast(_Slot(item, bytes));
    _bytes += bytes;
  }

  /// Removes and returns everything buffered, oldest first, resetting byte
  /// accounting. The dropped counter is preserved.
  List<T> drain() {
    if (_slots.isEmpty) return const [];
    final out = List<T>.generate(
      _slots.length,
      (_) => _slots.removeFirst().item,
      growable: false,
    );
    _bytes = 0;
    return out;
  }

  /// Reads and resets the dropped counter (delta since the last read).
  int takeDroppedDelta() {
    final delta = _dropped;
    _dropped = 0;
    return delta;
  }
}

class _Slot<T> {
  const _Slot(this.item, this.bytes);
  final T item;
  final int bytes;
}
