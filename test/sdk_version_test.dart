import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/src/engine/worker/uploader.dart';

/// [sessionlySdkVersion] is stamped into every batch's `sdk.version`, so it is
/// the ONLY thing that identifies which SDK build produced the data. It is a
/// hand-kept constant (Dart cannot read pubspec at runtime without a build
/// step), so this test pins it to the package version: bump one and you must
/// bump the other, or a release silently reports the wrong version — which is
/// exactly how 0.1.1–0.1.3 all shipped still reporting `0.1.0-dev`.
void main() {
  test('sessionlySdkVersion matches the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
    expect(
      sessionlySdkVersion,
      match!.group(1),
      reason:
          'sessionlySdkVersion (uploader.dart) must match pubspec version — '
          'bump both on every release.',
    );
  });
}
