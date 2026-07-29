# sessionly_flutter

The Flutter SDK for **Sessionly** — first-party, privacy-first product analytics
for iOS and Android.

Drop it in and you get screen views, taps, rage/dead taps, scroll depth, app
lifecycle, uncaught errors and frame-timing performance **captured
automatically** — plus `track` / `identify` / `screen` for the moments only you
know about. It is built to stay out of your app's way:

- **Never blocks the UI.** Capture is a constant-time enqueue on the main
  isolate (< 1 ms); serialize, compress, persist and upload all happen on a
  background isolate.
- **Never throws into your app.** Every public call is wrapped; on failure it
  drops data rather than degrading the host app.
- **Never loses data quietly.** Events survive a crash or offline via an sqlite
  disk queue, then upload gzipped with backoff.
- **First-party by design.** Events go to *your* Sessionly ingest origin, not a
  third party.

> **Status:** `0.1.0`, first public release. The engine is device-verified on
> Android; iOS runs the same pure-Dart path over standard plugins and is newly
> supported — please file anything platform-specific you hit.

Under the hood it implements the Dart side of Sessionly **wire protocol v1**
(event / context / envelope models, governed vocabulary, `props` limits,
UUIDv7) plus the capture engine (ring buffer → background isolate → sqlite disk
queue → gzip uploader).

> **New to the SDK?** Read **[USAGE.md](USAGE.md)** — a practical event guide:
> what to log, when to log it, which events fire automatically, the
> "[which event, when](USAGE.md#which-event-when)" playbook, naming/props
> conventions, timing rules, and what never to log.

## Install

Add it as a git dependency, pinned to a tag (there is no pub.dev release yet):

```yaml
dependencies:
  sessionly_flutter:
    git:
      url: https://github.com/afkcodes/sessionly-flutter.git
      ref: v0.1.0
```

Then `flutter pub get`. Works on iOS and Android — it is pure Dart over
standard plugins (`http`, `path_provider`, `sqlite3`).

You need a **write key**, which you get by creating a workspace at
**https://sessionly.afk.codes** → the project's Install page shows it once. The
key is public by design (it ships in your app; it is write-only and revocable).

## Quickstart

```dart
import 'package:sessionly_flutter/sessionly_flutter.dart';

Future<void> main() async {
  // init is cheap on the main isolate (< 5 ms); the isolate spawn, disk open,
  // and config fetch all happen async, off the first frame.
  await Sessionly.init(SessionlyConfig(
    writeKey: 'sly_w_...',
    endpoint: Uri.parse('https://sessionly.afk.codes'),
  ));

  Sessionly.track('checkout_completed', props: {'value': 499});
  Sessionly.identify('user_123');
  Sessionly.screen('CheckoutPage'); // manual override if not using the observer
  Sessionly.reset();                // on logout

  await Sessionly.flush();    // force an upload (tests / lifecycle hooks)
  await Sessionly.shutdown(); // tests / example-app exit
}
```

## Auto-capture

Wrap your app in `SessionlyRoot` (the tap-capture install point) and add a
`SessionlyNavigatorObserver` to your app's `navigatorObservers` (or, with
go_router, its `observers`). Lifecycle, error, and performance surfaces install
themselves during `Sessionly.init` — no wiring needed — and honor the
per-surface `AutoCapture` flags.

```dart
runApp(
  SessionlyRoot(
    child: MaterialApp(
      navigatorObservers: [SessionlyNavigatorObserver()],
      home: const HomePage(),
    ),
  ),
);
```

Surfaces:

- **Screens** — `screen_view` (with a `previous_screen` edge) + `navigation`
  on pop/replace, plus `slow_screen_load` when a route's first frame is slow.
- **Taps** — a root `Listener` records position + timestamp in O(1); a
  post-frame, bounded element-walk resolves a **content-free** identity
  (widget type / key / explicit semantics label — never text or input values).
- **Frustration** — on-device sliding windows: `rage_tap`, `dead_tap`,
  `nav_thrash`.
- **Lifecycle** — `app_open`, `first_open` (once, persisted), foreground /
  background (background triggers a flush).
- **Errors** — chained `FlutterError.onError` + `PlatformDispatcher.onError`
  (the previous handler is always called). Only a message **hash** and a
  package-filtered stack digest are sent unless `captureErrorMessages: true`.
- **Performance** — windowed frame timings (`slow_frame_burst` /
  `frozen_frame`) and a background-isolate ANR watchdog.

### Engine guarantees (docs/05, Rule 0)

- **O(1) capture.** Per event on the main isolate: no-throw guard + stamp
  (event_id, ts) + ring-buffer add. Everything else — serialize, scrub,
  sessionize, sqlite, gzip, HTTP — runs in a dedicated background isolate.
- **Never throws into the host app.** Every public entry is wrapped; internal
  failures are counted and reported via a sampled `sdk_health` event.
- **Bounded + offline-first.** 2 MB memory ring buffer (drop-oldest), 10 MB
  crash-safe sqlite queue (LRU eviction), batched gzip uploads with exponential
  backoff + jitter. Fail open: if the backend is down, buffer then drop — never
  degrade the app.
- **SDK-side sessionization**, persisted `anonymous_id`, remote config with a
  kill switch (`enabled: false` → capture becomes a no-op).

## Protocol conformance

The wire protocol has one source of truth in the Sessionly platform (zod
schemas). Because Dart cannot import them, conformance is proven by **contract
tests** that validate against the same golden JSON fixtures, vendored here under
`fixtures/` and kept in sync with upstream. If the SDK ever drifts from the
protocol, these tests fail.

```dart
import 'package:sessionly_flutter/sessionly_flutter.dart';

final batch = EventBatch.fromJson(payload); // throws SessionlyProtocolError on bad input
final wire = batch.toJson();                // exact wire shape, round-trips
```

## Development

```sh
flutter pub get
dart format .
flutter analyze --fatal-infos
flutter test
```

Lints use the `very_good_analysis` rule set (Rule 4.4); zero analyzer issues.

## Performance gates

The Rule 0 / docs/05 budgets are executable. See **[PERF.md](PERF.md)** for the
full table and how to run each locally.

```sh
# Pure-Dart micro-benchmarks — the CI perf gate. Exits non-zero on a breach.
dart run benchmark/main.dart                       # human table + JSON (best-of-3)

# dart:ui-bound budgets (frame-timings handler, tap record+schedule):
flutter test test/perf/frame_and_tap_bench_test.dart

# On-device added-jank harness (baseline vs enabled) and end-to-end:
cd example && flutter test integration_test/perf_test.dart -d <device> --profile
```

## Example app

`example/` is a small 4-screen app (home with a rage-tap target and a dead zone,
a scrollable list, a form, and a heavy animated screen) wired with
`SessionlyRoot` + `SessionlyNavigatorObserver` + `Sessionly.init`. Endpoint /
write key / enabled come from `--dart-define` (`FP_ENDPOINT`, `FP_WRITE_KEY`,
`FP_ENABLED`; defaults target the emulator loopback). It doubles as the perf and
end-to-end harness target and carries a debug overlay of `Sessionly.debugStats()`.
