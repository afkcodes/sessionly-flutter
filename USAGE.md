# Using sessionly_flutter — event guide

A practical guide to **what to log, when to log it, and why** with the Sessionly
Flutter SDK. If you only read one section, read [Which event, when](#which-event-when).

- New here? Start with [Setup](#1-setup).
- Want the mental model? [How events work](#2-how-events-work).
- Just want the "do this / not that" cheat sheet? [Which event, when](#which-event-when)
  and [Timing rules of thumb](#6-timing-rules-of-thumb).

> **The one rule that governs everything:** the SDK sends **behaviour, never
> content**. Field *identities*, not field *values*. A message *hash*, not the
> message. A tap's *coordinates* and *target key*, not the text on the button.
> Never put personally identifiable information (PII) in an event name or in
> `props`. See [What never to log](#8-what-never-to-log).

---

## 1. Setup

```dart
import 'package:sessionly_flutter/sessionly_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // init is cheap on the main isolate (< 5 ms); the isolate spawn, disk open,
  // and config fetch all happen async, off the first frame.
  await Sessionly.init(SessionlyConfig(
    writeKey: 'sly_w_...',
    endpoint: Uri.parse('https://sessionly.afk.codes'),
    // autoCapture: AutoCapture.all,   // the default — see the table below
  ));

  runApp(
    SessionlyRoot(                       // installs tap / scroll capture
      child: MaterialApp(
        navigatorObservers: [SessionlyNavigatorObserver()],  // screen_view + navigation
        home: const HomePage(),
      ),
    ),
  );
}
```

Two wiring points give you the whole auto-capture surface:

- **`SessionlyRoot`** wraps your app — the install point for tap and scroll capture.
- **`SessionlyNavigatorObserver`** in `navigatorObservers` (or, with go_router,
  its `observers`) — emits `screen_view` + `navigation`. Lifecycle, error, and
  performance surfaces install themselves during `init`; no wiring needed.

### Configuration (`SessionlyConfig`)

| Option | Default | What it does |
|---|---|---|
| `writeKey` | — (required) | Your project's write key (`sly_w_...`). |
| `endpoint` | — (required) | Your ingest URL. |
| `autoCapture` | `AutoCapture.all` | Per-surface toggles (below). |
| `enabled` | `true` | Kill switch — `false` makes every capture a no-op. |
| `flushIntervalSeconds` | `30` | How often batches upload. |
| `flushBatchSize` | `50` | Events per upload batch. |
| `sessionTimeoutMinutes` | `30` | Inactivity gap that ends a session. |
| `slowScreenLoadMs` | `1000` | Route slower than this → `perf/slow_screen_load`. |
| `httpSlowThresholdMs` | `3000` | Request slower than this → `perf/http_slow`. |
| `captureErrorMessages` | `false` | Keep it `false` — otherwise raw error text (possible PII) is sent instead of a hash. |
| `debugRethrow` | `false` | Rethrow internal SDK errors in tests only. |

### Turning surfaces on/off (`AutoCapture`)

Every auto surface is on by default. Disable individually:

```dart
SessionlyConfig(
  writeKey: 'sly_w_...',
  endpoint: Uri.parse('https://sessionly.afk.codes'),
  autoCapture: AutoCapture(inputs: false),  // everything on except input capture
  // or AutoCapture.none for a fully manual setup
)
```

Toggles: `screens`, `taps`, `scroll`, `inputs`, `lifecycle`, `errors`, `perf`.

---

## 2. How events work

Every event has a **`type`** and a **`name`**. Non-custom types draw their name
from a **fixed vocabulary** (the wire protocol governs it — you can't emit a typo
as a new event). There are exactly two things you do:

1. **Nothing** — the SDK auto-captures the whole `auto` / `lifecycle` /
   `frustration` / `perf` / `error` surface for you.
2. **`Sessionly.track(...)`** — you log your own **business events** (`type: custom`).

Plus three identity/navigation verbs: `identify`, `reset`, `screen`.

| `type` | Who emits it | Examples |
|---|---|---|
| `auto` | SDK (+ your `screen`) | `screen_view`, `tap`, `scroll_depth`, `input_focus`, `input_abandon`, `navigation` |
| `lifecycle` | SDK | `app_open`, `first_open`, `app_foreground`, `app_background`, `session_start`, `session_end` |
| `frustration` | SDK | `rage_tap`, `dead_tap`, `nav_thrash` |
| `perf` | SDK (+ your HTTP tracker) | `slow_frame_burst`, `frozen_frame`, `slow_screen_load`, `http_slow` |
| `error` | SDK | `flutter_error`, `crash`, `http_error` |
| `identity` | You | `identify`, `reset` |
| `custom` | **You** (`track`) | `checkout_completed`, `plan_upgraded`, … |

---

## 3. Events the SDK captures for you (don't log these yourself)

These fire automatically. This table is mostly here so you understand **what
you already get for free** and don't duplicate it with custom events.

| Event | Fires when… | Key `props` | Toggle |
|---|---|---|---|
| `auto/screen_view` | a route is pushed/replaced (via the observer), or you call `Sessionly.screen()` | `previous_screen` edge | `screens` |
| `auto/navigation` | a route is popped/replaced | route edge | `screens` |
| `auto/tap` | a tap resolves to a widget target | `target` (key/type/semantics — never text), normalized `x`,`y` in 0..1 | `taps` |
| `auto/scroll_depth` | a scrollable screen is **left** — emits the deepest bucket reached | `depth_pct` ∈ {25, 50, 75, 100} | `scroll` |
| `auto/input_focus` | a text field with an explicit `Semantics` label gains focus | `field` (the label), `screen` | `inputs` |
| `auto/input_abandon` | focus leaves that field | `field`, `dwell_ms`, `had_input` (a **boolean** — was anything typed; never the text) | `inputs` |
| `lifecycle/app_open` | the app is opened | — | `lifecycle` |
| `lifecycle/first_open` | the **first ever** open (persisted) | — | `lifecycle` |
| `lifecycle/app_foreground` `app_background` | app moves to/from foreground (background triggers a flush) | — | `lifecycle` |
| `lifecycle/session_start` `session_end` | a session begins/ends (inactivity `sessionTimeoutMinutes`) | — | `lifecycle` |
| `frustration/rage_tap` | many taps on one target in a short window | `target`, `count`, `x`, `y` | `taps` |
| `frustration/dead_tap` | a tap on a non-interactive target that does nothing | `target`, `x`, `y` | `taps` |
| `frustration/nav_thrash` | rapid back-and-forth navigation | — | `screens` |
| `perf/slow_screen_load` | a route's first frame lands later than `slowScreenLoadMs` | timing | `perf` |
| `perf/slow_frame_burst` `frozen_frame` | windowed jank / a frozen frame | timing | `perf` |
| `perf/http_slow` | a request you recorded exceeds `httpSlowThresholdMs` | `host`, `path` (both PII-scrubbed), `method`, `status`, `duration_ms` | opt-in (below) |
| `error/flutter_error` `crash` `http_error` | an uncaught error / crash | message **hash** + package-filtered stack digest (not raw text unless `captureErrorMessages`) | `errors` |

**Field identity for inputs is opt-in per field.** `input_focus`/`input_abandon`
only fire for fields you deliberately label:

```dart
Semantics(
  label: 'card_number',            // this label is the ONLY thing that leaves the device
  textField: true,
  child: TextField(controller: _cardController),
)
```

Unlabelled fields are ignored — a privacy-safe default.

---

## 4. Events **you** log

### `Sessionly.track(name, props:)` — your business events

This is the workhorse. Every call creates a `custom` event. Log the **outcomes
that matter to your product**: the moment a user *completes* something meaningful.

```dart
Sessionly.track('checkout_completed', props: {
  'value_minor': 4990,       // 49.90 in minor units — a number, not "$49.90"
  'currency': 'usd',
  'item_count': 3,
  'payment_method': 'card',  // a category, never a card number
});
```

### `Sessionly.screen(name)` — manual screen views

Only if you're **not** using `SessionlyNavigatorObserver` (e.g. a custom
tab/router). If you use the observer, don't call this — you'd double-count.

```dart
Sessionly.screen('CheckoutPage');
```

### `Sessionly.identify(userId)` — attach a stable user id

Call it the moment you know who the user is — right after **sign-in / sign-up**,
and on **app start if a session is already restored**. Use your own stable id
(a UUID or account id), never an email or phone number.

```dart
Sessionly.identify('user_8f3a1c');   // ✅ opaque id
// Sessionly.identify(user.email);    // ❌ that's PII
```

### `Sessionly.reset()` — clear identity on logout

```dart
Future<void> signOut() async {
  await auth.signOut();
  Sessionly.reset();     // subsequent events are anonymous again
}
```

### Slow-HTTP capture (opt-in) — `Sessionly.httpTracker`

Flutter can't auto-hook the network stack, so slow-request capture is explicit.
Either wrap your client, or record requests yourself. Only requests slower than
`httpSlowThresholdMs` emit `perf/http_slow`; host/path are scrubbed of
credentials and query strings before anything leaves the device.

```dart
// Option A — wrap a package:http client (times every request automatically):
final client = SessionlyHttpClient(tracker: Sessionly.httpTracker);
await client.get(Uri.parse('https://api.example.com/things'));

// Option B — report from your own client / dio interceptor:
Sessionly.httpTracker.recordRequest(uri, 'POST', response.statusCode, elapsedMs);
```

---

## Which event, when

The heart of it. Map the **user moment** to the **right call**.

| The user just… | Log this | Notes |
|---|---|---|
| opened the app | *(nothing)* | `app_open` / `first_open` are automatic |
| moved to a new screen | *(nothing)* | the observer emits `screen_view` |
| tapped a button | *(nothing)* | `tap` is automatic (with coords) |
| scrolled an article to the end | *(nothing)* | `scroll_depth` fires on screen exit |
| signed in or signed up | `identify(id)` + a `track('signed_in' / 'signed_up')` | identify first, then the milestone |
| signed out | `reset()` | clears identity |
| finished onboarding | `track('onboarding_completed', props: {'steps': 4})` | a milestone, not each step's tap |
| added to cart | `track('added_to_cart', props: {'sku': ..., 'qty': ...})` | the outcome, once |
| completed a purchase | `track('purchase_completed', props: {'value_minor': ..., 'currency': ...})` | see [revenue](#recording-revenue) |
| started a subscription / upgraded a plan | `track('plan_upgraded', props: {'from': 'free', 'to': 'pro'})` | |
| performed a search | `track('search_performed', props: {'result_count': 12})` | log the **count**, never the query text (PII) |
| shared / invited someone | `track('content_shared', props: {'channel': 'link'})` | |
| hit a feature they can't use (paywall, limit) | `track('paywall_viewed', props: {'trigger': 'export_limit'})` | great for funnel/friction analysis |
| succeeded at your app's core action | `track('<core_action>_completed')` | your "north-star" event |
| got frustrated (rage/dead tap) | *(nothing)* | frustration is auto-detected |
| experienced a slow request | *(nothing, if you wired the tracker)* | `http_slow` fires past the threshold |

**Rule of thumb:** if the SDK already captures it (a tap, a screen, a scroll, an
error), **don't** re-log it as a custom event. Reserve `track` for **business
meaning** the SDK can't infer — "the user achieved X".

### Recording revenue

Revenue is a first-class concept in the wire protocol (`revenue/purchase` with
typed `amount_minor` / `currency` / `provider`), but the Flutter convenience API
does not yet surface a dedicated `purchase()` helper. Today, record purchases as
a custom event and keep money in **minor units as a number**:

```dart
Sessionly.track('purchase_completed', props: {
  'value_minor': 4990,   // integer minor units — not "49.90", not a formatted string
  'currency': 'usd',
  'provider': 'stripe',
  'recurring': false,
});
```

---

## 5. Naming & props conventions

**Event names** — `snake_case`, start with a letter, past-tense verbs for
outcomes (`checkout_completed`, not `Checkout` or `completeCheckout`). Keep a
small, stable vocabulary; don't mint a new name per variation — put the variation
in `props`. Names may be up to 128 chars.

```
✅ video_played        ❌ VideoPlayed
✅ plan_upgraded       ❌ user upgraded their plan!!!
✅ level_completed  props:{'level': 7}      ❌ level_7_completed, level_8_completed, …
```

**`props`** carry the detail. The limits (enforced on the wire):

- Values are **scalars** or **shallow objects** (nesting depth ≤ 2).
- At most **40 keys**; total serialized size ≤ **16 KB**.
- Prefer numbers for anything you'll aggregate (`value_minor`, `count`, `qty`).
- Prefer **categories** over free text (`payment_method: 'card'`, not a card number;
  `tier: 'pro'`, not a price string).

---

## 6. Timing rules of thumb

- **Log the outcome, not the intent.** `purchase_completed` on the success
  callback — not when the pay button is tapped (the tap is already captured, and
  the purchase may fail).
- **Identify as early as you truthfully can.** Right after auth, and on app start
  if a session is restored — so events attach to the right person from the first frame.
- **Reset on logout**, before the next user could act.
- **Don't log inside `build()` or on every frame.** Log on the event/callback that
  represents the thing happening once.
- **One event per outcome.** Guard against double-firing on retries/rebuilds.
- **You never need to `flush()` in normal use** — batching + the background flush
  handle it. `flush()` is for tests and lifecycle hooks.

---

## 7. Worked recipes

**Onboarding funnel** — one milestone per completed step, so you can measure drop-off:

```dart
Sessionly.track('onboarding_step_completed', props: {'step': 'profile'});
Sessionly.track('onboarding_step_completed', props: {'step': 'notifications'});
Sessionly.track('onboarding_completed', props: {'total_steps': 3});
```

**Checkout** — identify, then the outcome (the taps/screens in between are automatic):

```dart
Sessionly.identify(account.id);
// … user taps through cart → shipping → pay (all auto-captured) …
Sessionly.track('purchase_completed', props: {
  'value_minor': order.totalMinor, 'currency': order.currency, 'item_count': order.items.length,
});
```

**Search** — count only, never the query:

```dart
Sessionly.track('search_performed', props: {'result_count': results.length});
```

---

## 8. What never to log

Never place these in an event **name** or in **`props`** — the SDK is built to
avoid capturing them, and you shouldn't re-introduce them:

- Names, emails, phone numbers, usernames, addresses.
- Passwords, tokens, API keys, card/account numbers.
- The **contents** of any text field, search box, or message.
- Raw URLs with query strings (they smuggle tokens/emails — the HTTP tracker
  strips these for you; do the same in custom props).
- Precise location, government ids, health data.

Use an **opaque user id** with `identify`, **categories** instead of free text,
and **counts/amounts** instead of the underlying data.

---

## 9. Verifying what you log

- **On device:** `Sessionly.debugStats()` returns a live snapshot
  (`captured`, `buffered`, `dropped`, `internal_errors`) — great for a debug overlay.
- **In the dashboard:** open the **Sessions** page and pick a session to see its
  **event-reconstructed timeline** (plays forward, oldest → newest) — every
  screen, tap, scroll, input, and custom event in order. Tap coordinates feed
  **Heatmaps**; frustration + input abandonment feed **Friction**; `http_slow`
  feeds **Performance**.

---

## See also

- [README](README.md) — install, engine guarantees, protocol conformance.
- [PERF.md](PERF.md) — the main-thread performance budgets and how they're gated.
- **Event vocabulary & data model** — the full governed event list
  and typed props, defined once for all SDKs.
- **SDK design** — capture-surface internals and performance budgets.
</content>
</invoke>
