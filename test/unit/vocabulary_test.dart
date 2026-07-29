import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

/// Hard-coded expectations so any drift from the `packages/core` vocabulary
/// (a rename, removal, or accidental addition) fails loudly here (Rule 2.1).
void main() {
  test('event types match the protocol set', () {
    expect(EventType.values.map((e) => e.name).toSet(), {
      'auto',
      'custom',
      'lifecycle',
      'error',
      'frustration',
      'perf',
      'identity',
      'revenue',
    });
  });

  test('auto names', () {
    expect(autoNames, {
      'screen_view',
      'tap',
      'scroll_depth',
      'input_focus',
      'input_abandon',
      'navigation',
      'flag_exposure',
      'experiment_exposure',
    });
  });

  test('lifecycle names', () {
    expect(lifecycleNames, {
      'app_open',
      'app_foreground',
      'app_background',
      'session_start',
      'session_end',
      'first_open',
    });
  });

  test('frustration names', () {
    expect(frustrationNames, {
      'rage_tap',
      'dead_tap',
      'nav_thrash',
      'retry_burst',
    });
  });

  test('error names', () {
    expect(errorNames, {'crash', 'flutter_error', 'http_error', 'js_error'});
  });

  test('perf names', () {
    expect(perfNames, {
      'slow_frame_burst',
      'frozen_frame',
      'slow_screen_load',
      'http_slow',
      'web_vital',
    });
  });

  test('identity names', () {
    expect(identityNames, {'identify', 'alias', 'reset'});
  });

  test('revenue names', () {
    expect(revenueNames, {'purchase'});
  });

  test('custom name length cap', () {
    expect(customNameMaxLength, 128);
  });

  test('isVocabularyName and isRecommendedCustomName', () {
    expect(isVocabularyName(EventType.auto, 'tap'), isTrue);
    expect(isVocabularyName(EventType.auto, 'frobnicate'), isFalse);
    expect(isRecommendedCustomName('checkout_completed'), isTrue);
    expect(isRecommendedCustomName('Checkout Completed'), isFalse);
    expect(isRecommendedCustomName('x' * 129), isFalse);
  });
}
