# Performance budgets & gates

The Rule 0 / docs/05 main-thread budgets, made executable. Each has a gate that
fails CI (or an on-device run) when breached.

Host = Linux x64, Dart 3.11.5 (CI-class). Device = Xiaomi 22021211RI, Android 16,
profile build.

## Budgets vs. latest measured

| Budget (source)                                    | Ceiling     | Measured (host)        | Gate |
|----------------------------------------------------|-------------|------------------------|------|
| Enqueue `captureEvent` p99 (Rule 0.1)              | < 1 ms      | **1.28 µs** (best of 3) | `dart run benchmark/main.dart` |
| `addTimingsCallback` handler, mean/frame (docs/05) | < 0.1 ms    | **0.16 µs**            | `flutter test test/perf/frame_and_tap_bench_test.dart` |
| Tap record+schedule main-thread p99 (docs/05)      | < 0.5 ms    | **0.09 µs** (w/ coords) | same |
| Scroll-notification record p99 (docs/05)           | < 0.05 ms   | **0.04 µs**            | `flutter test test/perf/frame_and_tap_bench_test.dart` |
| SDK init on main isolate (docs/05)                 | < 5 ms      | async off-frame (design)| n/a |
| Added janky build frames vs baseline (docs/05)     | 0 (+1 tol.) | **+0** (base 1 → enabled 1, capture wave active) ✓ | `integration_test/perf_test.dart` |
| App PSS growth over 5-min soak (leak smoke)        | < 10 MB     | **−8.1 MB** (no leak) ✓ | soak-lite (below) |
| On-device e2e: events counted server-side          | all sent    | **64 captured, all surfaces present** ✓ | `integration_test/e2e_test.dart` |
| Offline → app unaffected, delivery catches up      | Rule 0.7    | **held flat, then caught up** ✓ | airplane-mode toggle |

Enqueue (best of 3): p50 0.77 / p99 1.28 / mean 0.84 µs — ~780x under budget. Info (host): ring add p99 ~0.06 µs; drain ~0.019 µs/ev; UUIDv7 p99 ~0.77 µs.

Capture-wave surfaces: tap coordinates are resolved post-frame (screen-normalized arithmetic) — the synchronous tap hot path is unchanged (host p99 0.09 µs). Scroll depth is an O(1) `max` update per notification (host p99 0.04 µs, no layout read). Input focus/abandon and the opt-in HTTP tracker emit through the same O(1) capture gate. Device-verified below: with all four surfaces active the enabled run added **0** janky frames over baseline.

### On-device numbers (Xiaomi 22021211RI, Android 16, profile)

- **Added jank, capture wave active** (baseline=SDK disabled vs enabled, identical
  journey now exercising scroll/inputs/http, 704/703 frames sampled): janky build
  frames **1 → 1** (**added +0**, within the ±1 docs/05 tolerance); avg build
  **1.06 → 1.06 ms** (unchanged), worst build 20.14 → 18.53 ms; avg raster
  2.43 → 2.43 ms, worst raster 25.90 → 27.24 ms. Zero added cost from the new
  capture surfaces.
- **End-to-end**: the scripted journey captured **64 events on-device** (0 dropped,
  0 internal errors), and every capture-wave surface landed server-side in
  ClickHouse: `tap` with normalized x/y in [0,1] (avg x 0.45 on centred targets),
  `scroll_depth` (`depth_pct=50` on list exit), `input_focus`/`input_abandon`
  (field identity = the explicit `Semantics` label; `had_input` truthful —
  `true` for the two prefilled fields, `false` for the untouched notes field),
  `http_slow` (a forced 4200 ms request whose `user:secret@` credentials and
  `?token=…&email=…` query string were BOTH stripped → `host=api.example.com`,
  `path=/v1/checkout/session`), plus `rage_tap`/`dead_tap` carrying coordinates
  and the rest of the auto-capture surface (screen_view, navigation, lifecycle,
  identify, slow_frame_burst, custom).
- **Offline (Rule 0.7)**: with the app driven under airplane mode the
  server-side count held flat (events buffered on-device, app unaffected); on
  reconnect the durable sqlite queue drained and the count resumed rising
  (delayed delivery). Recovery from the crash-safe queue on restart, since the
  live uploader backs off up to the 5-min jittered cap.
- **Soak-lite**: 5-min continuous drive from a warmed baseline → whole-app
  TOTAL PSS **175.7 → 167.4 MB (−8.1 MB)**, oscillating 159–171 MB with no
  upward trend → no leak. (A cold-start baseline shows +26 MB, but that is
  one-time warmup — screens, animation/GPU buffers, image cache — not growth.
  An independent orchestrator run measured 139.7 → 61.4 MB over its own 5-min
  loop — same conclusion.)
- **Auth-halt visibility**: a 401 (revoked/rotated write key) halts the uploader
  by design; it now surfaces as `upload_halts` in `sdk_health` telemetry and
  `upload_halted` in `Sessionly.debugStats()` — a halted SDK is no longer
  indistinguishable from a healthy one. Testing gotcha: airplane mode does NOT
  cut an `adb reverse` USB tunnel; simulate offline by removing the tunnel
  (`adb reverse --remove tcp:8788`) when the endpoint rides USB.

## Running each gate locally

```sh
cd sdks/flutter
dart run benchmark/main.dart                 # pure-Dart CI gate; non-zero on breach; best-of-3, +JSON
flutter test test/perf/frame_and_tap_bench_test.dart   # dart:ui budgets (also in the normal suite)
```

### On-device (profile) — `flutter test` has no `--profile`, so use `flutter drive`

```sh
cd sdks/flutter/example
# Added-jank harness (baseline vs enabled):
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/perf_test.dart -d 895e7ead --profile
# End-to-end: HOST serves ingest on 0.0.0.0:8788 with a provisioned write key
# (LAN IP via `ip -4 addr`; adb reverse tcp:8788 tcp:8788 + 127.0.0.1 as fallback):
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/e2e_test.dart -d 895e7ead --profile \
  --dart-define=FP_ENDPOINT=http://<LAN-IP>:8788 --dart-define=FP_WRITE_KEY=<key>
# Verify server-side:
docker exec sessionly-clickhouse-1 clickhouse-client --user sessionly \
  --password sessionly_dev_pw --database sessionly -q \
  "SELECT type,name,count(DISTINCT event_id) c FROM events WHERE project_id='<PID>' GROUP BY type,name"
# Offline: count → airplane-mode enable → drive → count flat → disable/restart → catch-up:
adb -s 895e7ead shell cmd connectivity airplane-mode enable   # (fallback: kill host ingest)
# Soak-lite: TOTAL PSS before/after a 5-min drive loop from a warmed baseline:
adb -s 895e7ead shell dumpsys meminfo dev.sessionly.sessionly_example | grep 'TOTAL PSS'
```

## Notes

- Thresholds have ~800-1000x headroom → stable CI gate; still best-of-3.
- Precise SDK-only steady-state memory attribution (the < 2 MB soak) is a Phase 1
  exit deliverable; the soak-lite is a whole-app leak smoke-test, not that.
- The example allows cleartext HTTP (dev only); reads `FP_ENDPOINT` /
  `FP_WRITE_KEY` / `FP_ENABLED` from `--dart-define`.
