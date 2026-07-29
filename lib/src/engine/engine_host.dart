/// The seam between the main-isolate capture gate and the engine. In production
/// the host is an isolate boundary; in tests it wraps an [Engine] directly so
/// the whole pipeline runs in-process without spawning anything.
library;

import 'dart:async';

import 'package:sessionly_flutter/src/engine/engine.dart';

/// Receives drained record batches and exposes flush/shutdown control.
abstract interface class EngineHost {
  /// Hands a drained batch of raw records to the engine. Fire-and-forget: the
  /// main isolate never awaits engine work.
  void submit(List<Map<String, Object?>> records);

  /// Forces an upload attempt and waits for it to settle.
  Future<void> flush();

  /// Flushes, ends the session, and releases engine resources.
  Future<void> shutdown();
}

/// A host that can report a terminal upload halt (a 401 auth failure) back to
/// the main isolate so it surfaces in `Sessionly.debugStats`. Kept separate
/// from [EngineHost] so test doubles need not implement it (Rule 0.3: a halt
/// must never be silent, but only the real hosts can observe the uploader).
abstract interface class HaltAware {
  /// `true` once uploads have terminally halted on a 401 (bad/rotated key).
  bool get authHalted;
}

/// A host that exposes the last delivered feature-flag map to the main isolate
/// (docs/06 § in-app flag channel), so `Sessionly.flag()` reads it synchronously
/// (Rule 0.1). The real isolate host relays it over the status port; the inline
/// host reads the engine's remote config directly. Separate from [EngineHost]
/// so plain test doubles need not implement it.
abstract interface class FlagAware {
  /// The delivered flag map (`key -> {enabled, value}`); empty until a fetch.
  Map<String, Object?> get flags;
}

/// A host that exposes the last delivered running-experiment map plus the
/// stable actor seed to the main isolate (docs/10 Suite modules), so
/// `Sessionly.experiment()` resolves a deterministic variant synchronously
/// (Rule 0.1). The real isolate host relays both over the status port; the
/// inline host reads the engine directly. Separate from [EngineHost] so plain
/// test doubles need not implement it.
abstract interface class ExperimentAware {
  /// The delivered experiment map (`key -> {flagKey, variants}`); empty until
  /// a fetch.
  Map<String, Object?> get experiments;

  /// The stable per-actor assignment seed (anonymous id); empty until it lands.
  String get assignmentSeed;
}

/// Runs the [Engine] in the current isolate. Used by tests and by any embedding
/// that opts out of a background isolate. Submits are serialized so engine
/// state is never mutated concurrently.
class InlineEngineHost
    implements EngineHost, HaltAware, FlagAware, ExperimentAware {
  /// Wraps an engine. Call [ready] to run engine startup before submitting.
  InlineEngineHost(this._engine);

  final Engine _engine;
  Future<void> _tail = Future<void>.value();

  @override
  bool get authHalted => _engine.authHalted;

  @override
  Map<String, Object?> get flags => _engine.flags;

  @override
  Map<String, Object?> get experiments => _engine.experiments;

  @override
  String get assignmentSeed {
    try {
      return _engine.anonymousId;
    } on Object {
      // Identity not yet loaded — no seed, so the caller assigns nothing.
      return '';
    }
  }

  /// Runs engine startup (state load, timers, resume of queued rows).
  Future<void> ready() => _engine.start();

  @override
  void submit(List<Map<String, Object?>> records) {
    _tail = _tail.then((_) => _engine.submit(records));
  }

  @override
  Future<void> flush() async {
    await _tail;
    await _engine.flush();
  }

  @override
  Future<void> shutdown() async {
    await _tail;
    await _engine.shutdown();
  }
}
