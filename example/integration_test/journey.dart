// The scripted user journey: visit all four screens, scroll the list hard, type
// in the form, watch the heavy animation, then fire a rage-tap burst and a dead
// tap. Shared by the perf harness (perf_test.dart) and the on-device e2e run
// (e2e_test.dart).
//
// It NEVER calls pumpAndSettle: on a real device the soft-keyboard (IME) insets
// animation and the heavy screen's repeating animation never reach "idle", so
// pumpAndSettle would hang to its 10-minute timeout. Every wait is a bounded
// pump, so the journey is deterministic on-device.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Tap a keyed widget, then drive a bounded number of frames (default enough
/// for a route transition) — no "wait for idle".
Future<void> _tapKey(WidgetTester tester, String key, {int frames = 32}) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await _pumpFrames(tester, frames);
}

/// Drop the soft keyboard and let its inset animation run out under a bounded
/// pump (so nothing downstream waits on an IME that never settles).
Future<void> _dismissKeyboard(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await _pumpFrames(tester, 14);
}

/// Runs one full journey against the pumped example app. Assumes it starts on
/// the home screen and leaves it there.
Future<void> runJourney(WidgetTester tester) async {
  await _pumpFrames(tester, 12);

  // --- List screen: open, scroll hard, return. ---
  await _tapKey(tester, 'go_list');
  final list = find.byKey(const ValueKey('demo_list'));
  for (var i = 0; i < 6; i++) {
    await tester.fling(list, const Offset(0, -450), 2200);
    await _pumpFrames(tester, 16);
  }
  await tester.pageBack();
  await _pumpFrames(tester, 28);

  // --- Form screen: focus each field in turn (identity via Semantics label
  //     only). name/email are prefilled → their abandon carries had_input=true;
  //     notes is empty → focusing then leaving it carries had_input=false. No
  //     typing: a physical device's real IME owns the input connection, so the
  //     had_input branches are driven by genuine controller state, not the IME.
  await _tapKey(tester, 'go_form');
  await tester.tap(find.byKey(const ValueKey('field_name')));
  await _pumpFrames(tester, 8);
  await tester.tap(find.byKey(const ValueKey('field_email')));
  await _pumpFrames(tester, 8);
  await tester.tap(find.byKey(const ValueKey('field_notes')));
  await _pumpFrames(tester, 8);
  await _dismissKeyboard(tester);
  await _tapKey(tester, 'submit_form');
  await _dismissKeyboard(tester);
  await tester.pageBack();
  await _pumpFrames(tester, 28);

  // --- Heavy screen: infinite animation, so navigate WITHOUT settle and drive
  //     fixed frames through the transition + running animation. ---
  await tester.tap(find.byKey(const ValueKey('go_heavy')));
  await _pumpFrames(tester, 45);
  await tester.pageBack();
  await _pumpFrames(tester, 28);

  // --- Frustration: rage-tap one target fast, then a dead tap on the zone. ---
  final rage = find.byKey(const ValueKey('rage_target'));
  for (var i = 0; i < 6; i++) {
    await tester.tap(rage);
    await tester.pump(const Duration(milliseconds: 80));
  }
  await tester.tap(find.byKey(const ValueKey('dead_zone')));
  await tester.pump(const Duration(milliseconds: 500));

  // --- A couple of explicit custom events. ---
  await _tapKey(tester, 'track_custom');
  await _tapKey(tester, 'track_custom');
  await _pumpFrames(tester, 12);

  // --- Forced-slow HTTP: records a 4200 ms request whose URL carries
  //     credentials + a PII query string; the SDK strips both before emit. ---
  await _tapKey(tester, 'slow_http');
  await _pumpFrames(tester, 12);
}
