/// The single shared "where is the user now" holder. The navigator observer
/// writes it on every route change; tap capture, frustration windows, and
/// perf/error events all read it to stamp `screen`. Keeping one authority
/// avoids each surface re-deriving the current route.
library;

/// Notified on every screen transition with the (previous, next) edge.
typedef ScreenTransition = void Function(String? previous, String? next);

/// Mutable, main-isolate-only holder of the current screen name plus a tiny
/// listener fan-out for surfaces that react to transitions (e.g. nav_thrash).
class CurrentScreenTracker {
  final List<ScreenTransition> _listeners = <ScreenTransition>[];

  String? _current;

  /// The current screen name, or `null` before the first route resolves.
  String? get current => _current;

  /// Registers [listener] for future transitions.
  void addListener(ScreenTransition listener) => _listeners.add(listener);

  /// Removes a previously registered [listener].
  void removeListener(ScreenTransition listener) => _listeners.remove(listener);

  /// Sets the current screen to [next], firing listeners on a real change. A
  /// no-op when [next] equals the current value. Listener failures are isolated
  /// so one bad observer can never break capture (Rule 0.3).
  void update(String? next) {
    final previous = _current;
    if (previous == next) return;
    _current = next;
    // Iterate a copy: a listener may mutate the list (dispose) mid-notify.
    for (final listener in List<ScreenTransition>.of(_listeners)) {
      try {
        listener(previous, next);
      } on Object {
        // Swallowed: a frustration/analytics listener must not break routing.
      }
    }
  }
}
