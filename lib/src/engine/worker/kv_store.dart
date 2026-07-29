/// Tiny key-value seam for durable engine state: `anonymous_id`, `user_id`,
/// last session state, cached remote config. Backed by the same sqlite db as
/// the queue in production; [InMemoryKvStore] backs tests.
library;

/// String→string durable store. Async for the same Rule 0.2 reason as
/// [QueueStore]: no synchronous I/O anywhere.
abstract interface class KvStore {
  /// Reads [key], or `null` if unset.
  Future<String?> get(String key);

  /// Writes [value] at [key].
  Future<void> set(String key, String value);

  /// Deletes [key].
  Future<void> remove(String key);

  /// Releases resources.
  Future<void> close();
}

/// Well-known kv keys.
abstract final class KvKey {
  /// Persisted `anonymous_id`.
  static const String anonymousId = 'anonymous_id';

  /// Persisted `user_id`, when identified.
  static const String userId = 'user_id';

  /// Persisted current session id.
  static const String sessionId = 'session_id';

  /// Persisted last-activity Unix ms.
  static const String lastActivityMs = 'last_activity_ms';

  /// Persisted flag: `first_open` already emitted.
  static const String firstOpenDone = 'first_open_done';

  /// Cached remote config JSON.
  static const String remoteConfig = 'remote_config';
}

/// In-memory [KvStore] for tests and native-lib fallback.
class InMemoryKvStore implements KvStore {
  final Map<String, String> _map = {};

  @override
  Future<String?> get(String key) async => _map[key];

  @override
  Future<void> set(String key, String value) async => _map[key] = value;

  @override
  Future<void> remove(String key) async => _map.remove(key);

  @override
  Future<void> close() async {}
}
