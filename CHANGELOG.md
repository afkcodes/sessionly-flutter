# Changelog

## 0.1.0-dev

- Initial package scaffold.
- Wire protocol v1 Dart models: events, context, envelope, vocabulary,
  `props` limits, UUIDv7 generation and validation.
- Contract tests against the shared `packages/core` golden fixtures.
- Capture engine (P1-T7):
  - `Sessionly` facade (`init`/`track`/`identify`/`screen`/`reset`/`flush`/
    `shutdown`) with a no-throw guard on every entry point (Rule 0.3).
  - O(1) main-isolate capture path: bounded drop-oldest ring buffer +
    stamp-only capture gate, draining primitive records to the engine.
  - Dedicated background isolate running the pipeline: sessionization
    (30-min rotation, synthesized lifecycle events), identity
    (`anonymous_id` + identify/reset), PII scrub seam, props validation,
    crash-safe sqlite disk queue (WAL, 10 MB LRU eviction), and a gzip
    uploader (batch 50/30 s, backoff + jitter, 202/400/401/429/5xx policy).
  - Remote config + kill switch, self-telemetry (`sdk_health`), and a
    swappable platform adapter (`path_provider` / `package_info_plus`).
  - Dependencies: `sqlite3`, `http`, `path_provider`, `package_info_plus`.
- Auto-capture surfaces (P1-T8), all flowing through the O(1) capture gate and
  honoring the per-surface `AutoCapture` flags:
  - `SessionlyNavigatorObserver` — `screen_view` (with `previous_screen`) +
    `navigation` on pop/replace, route-name resolution, a shared
    `CurrentScreenTracker`, and `slow_screen_load` timing (go_router
    compatible).
  - `SessionlyRoot` — root `Listener` recording tap position + timestamp in
    O(1), then a post-frame, ≤25-ancestor element-walk that extracts a
    content-free identity (widget type / key / explicit semantics label —
    never text or input values).
  - Frustration detectors (`rage_tap`, `dead_tap`, `nav_thrash`) — on-device
    fixed-size sliding windows, O(1) per event.
  - Lifecycle — `app_open`, once-only persisted `first_open`, foreground /
    background with a background flush hint.
  - Errors — chained `FlutterError.onError` + `PlatformDispatcher.onError`
    (previous handler always called); message hash + package-filtered stack
    digest by default, opt-in sanitized message via `captureErrorMessages`.
  - Performance — windowed `addTimingsCallback` aggregation
    (`slow_frame_burst` / `frozen_frame`) and a background-isolate ANR
    watchdog. NOTE: the watchdog reports as `perf/frozen_frame` with
    `props.source == "watchdog"` (the protocol vocabulary has no
    `main_thread_stall` name).
  - Config: `captureErrorMessages` (default `false`), `slowScreenLoadMs`
    (default 1000), and an `AutoCapture.lifecycle` flag.
- Performance gates, example app, and on-device verification (P1-T9):
  - `benchmark/main.dart` — pure-Dart micro-benchmarks (enqueue p50/p99, ring
    buffer add/drain, UUIDv7) with machine-readable JSON + a human table,
    exiting non-zero when the Rule 0.1 enqueue p99 < 1 ms budget is breached.
    Wired as a CI step in the `dart` job (best-of-3 for stability).
  - `test/perf/frame_and_tap_bench_test.dart` — the `dart:ui`-bound budgets
    (`addTimingsCallback` mean < 0.1 ms/frame; tap record+schedule < 0.5 ms),
    asserted under `flutter test`.
  - `example/` — a real 4-screen demo app (`SessionlyRoot` +
    `SessionlyNavigatorObserver`, `--dart-define` config, a debug overlay of
    `Sessionly.debugStats()`) that doubles as the perf + e2e harness target,
    with `integration_test/perf_test.dart` (added-jank, baseline vs enabled) and
    `integration_test/e2e_test.dart` (drive journey against a live endpoint).
  - `PERF.md` — the budget table, how to run each gate, and latest numbers.
  - `Sessionly.debugStats()` — a read-only, no-throw snapshot of main-isolate
    counters (captured / buffered / dropped / internal_errors / enabled).
  - `config.enabled: false` is now honored on the main isolate too: the SDK
    installs no surfaces and spawns no engine isolate, and every capture entry
    is a true no-op (previously the kill switch was enforced only on the engine
    isolate). `CaptureGate` exposes `capturedTotal` / `droppedTotal` /
    `bufferedEvents` for the debug overlay.
