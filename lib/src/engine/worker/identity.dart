/// Identity state (docs/05 invariant 3). `anonymous_id` is generated once and
/// persisted; `identify(userId)` stamps subsequent events; `reset()` clears the
/// user and rotates the anonymous id.
library;

import 'package:sessionly_flutter/src/engine/worker/kv_store.dart';
import 'package:sessionly_flutter/src/protocol/uuid_v7.dart';

/// Durable identity for the engine.
class IdentityStore {
  /// Creates an [IdentityStore] over [kv].
  IdentityStore({required KvStore kv, required UuidV7Generator uuid})
    : _kv = kv,
      _uuid = uuid;

  final KvStore _kv;
  final UuidV7Generator _uuid;

  late String _anonymousId;
  String? _userId;

  /// Device-scoped anonymous id (`anon_`-prefixed).
  String get anonymousId => _anonymousId;

  /// Resolved user id, or `null` when anonymous.
  String? get userId => _userId;

  /// Loads persisted identity, minting and persisting an anonymous id on first
  /// run. Call once before use.
  Future<void> load() async {
    final existing = await _kv.get(KvKey.anonymousId);
    if (existing != null && existing.isNotEmpty) {
      _anonymousId = existing;
    } else {
      _anonymousId = _mintAnonymousId();
      await _kv.set(KvKey.anonymousId, _anonymousId);
    }
    _userId = await _kv.get(KvKey.userId);
  }

  /// Associates [userId] with this device and persists it.
  Future<void> identify(String userId) async {
    _userId = userId;
    await _kv.set(KvKey.userId, userId);
  }

  /// Clears the user and rotates the anonymous id (logout).
  Future<void> reset() async {
    _userId = null;
    _anonymousId = _mintAnonymousId();
    await _kv.remove(KvKey.userId);
    await _kv.set(KvKey.anonymousId, _anonymousId);
  }

  String _mintAnonymousId() => 'anon_${_uuid.generate().replaceAll('-', '')}';
}
