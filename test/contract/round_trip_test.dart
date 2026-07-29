import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

/// Programmatic round-trip: build each event type in Dart → `toJson` →
/// `fromJson` → `toJson` and assert the two wire maps are identical.
void main() {
  const ctx = EventCtx(
    appVersion: '2.3.1',
    build: '412',
    os: 'android',
    osVersion: '14',
    deviceClass: 'mid',
    locale: 'en-IN',
    network: 'wifi',
    screenW: 412,
    screenH: 915,
  );

  final ts = DateTime.utc(2026, 7, 18, 10, 30, 59, 821);

  SessionlyEvent build(EventType type, String name) {
    final common = {
      'eventId': '0190a1b2-c3d4-7e5f-8a0b-000000000001',
      'sessionId': '0190a1b2-c3d4-7e5f-8a0b-0000000000aa',
      'anonymousId': 'anon_2yQb8Fk3Lp',
    };
    return switch (type) {
      EventType.auto => AutoEvent(
        eventId: common['eventId']!,
        ts: ts,
        sessionId: common['sessionId']!,
        anonymousId: common['anonymousId']!,
        userId: null,
        screen: 'CheckoutPage',
        props: const {'target': 'PayButton'},
        ctx: ctx,
        name: name,
      ),
      EventType.lifecycle => LifecycleEvent(
        eventId: common['eventId']!,
        ts: ts,
        sessionId: common['sessionId']!,
        anonymousId: common['anonymousId']!,
        userId: null,
        screen: null,
        props: const {},
        ctx: ctx,
        name: name,
      ),
      EventType.frustration => FrustrationEvent(
        eventId: common['eventId']!,
        ts: ts,
        sessionId: common['sessionId']!,
        anonymousId: common['anonymousId']!,
        userId: 'user_42',
        screen: 'CheckoutPage',
        props: const {'taps': 5},
        ctx: ctx,
        name: name,
      ),
      EventType.error => ErrorEvent(
        eventId: common['eventId']!,
        ts: ts,
        sessionId: common['sessionId']!,
        anonymousId: common['anonymousId']!,
        userId: null,
        screen: null,
        props: const {'fatal': true},
        ctx: ctx,
        name: name,
      ),
      EventType.perf => PerfEvent(
        eventId: common['eventId']!,
        ts: ts,
        sessionId: common['sessionId']!,
        anonymousId: common['anonymousId']!,
        userId: null,
        screen: 'CheckoutPage',
        props: const {'duration_ms': 3400},
        ctx: ctx,
        name: name,
      ),
      EventType.identity => IdentityEvent(
        eventId: common['eventId']!,
        ts: ts,
        sessionId: common['sessionId']!,
        anonymousId: common['anonymousId']!,
        userId: 'user_42',
        screen: null,
        props: const {'plan': 'pro'},
        ctx: ctx,
        name: name,
      ),
      EventType.revenue => RevenueEvent(
        eventId: common['eventId']!,
        ts: ts,
        sessionId: common['sessionId']!,
        anonymousId: common['anonymousId']!,
        userId: 'user_42',
        screen: 'CheckoutPage',
        props: const {
          'amount_minor': 4999,
          'currency': 'USD',
          'provider': 'stripe',
          'recurring': false,
        },
        ctx: ctx,
        name: name,
      ),
      EventType.custom => CustomEvent(
        eventId: common['eventId']!,
        ts: ts,
        sessionId: common['sessionId']!,
        anonymousId: common['anonymousId']!,
        userId: null,
        screen: 'CheckoutPage',
        props: const {'value': 49.99, 'items': 3},
        ctx: ctx,
        name: name,
      ),
    };
  }

  final samples = <SessionlyEvent>[
    build(EventType.auto, 'tap'),
    build(EventType.lifecycle, 'app_open'),
    build(EventType.frustration, 'rage_tap'),
    build(EventType.error, 'crash'),
    build(EventType.perf, 'slow_screen_load'),
    build(EventType.identity, 'identify'),
    build(EventType.revenue, 'purchase'),
    build(EventType.custom, 'checkout_completed'),
  ];

  for (final event in samples) {
    test('round-trips ${event.type.name}/${event.name}', () {
      final json = event.toJson();
      final reparsed = SessionlyEvent.fromJson(json, path: 'events.0');
      expect(reparsed.runtimeType, event.runtimeType);
      expect(reparsed.toJson(), json);
    });
  }

  test('EventBatch round-trips programmatically', () {
    final batch = EventBatch(
      sentAt: DateTime.utc(2026, 7, 18, 10, 31, 2, 114),
      sdk: const SdkInfo(name: flutterSdkName, version: '0.3.0'),
      events: samples,
    );
    final json = batch.toJson();
    expect(EventBatch.fromJson(json).toJson(), json);
  });
}
