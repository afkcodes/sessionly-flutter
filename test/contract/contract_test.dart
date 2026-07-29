import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

/// Contract tests (Rule 2.1 / 5.2): the Dart protocol implementation is
/// validated against the SAME golden fixtures the TypeScript side uses. We read
/// them in place from `packages/core/fixtures` — never a copy.
void main() {
  final fixturesDir = _locateFixtures();

  group('valid fixtures', () {
    final files = _jsonFiles(Directory('${fixturesDir.path}/valid'));

    test('directory is present and populated', () {
      expect(files, isNotEmpty, reason: 'no valid fixtures found');
      // Guard against silently dropping fixtures: keep the count explicit.
      expect(files.length, 29);
    });

    for (final file in files) {
      final fixture = _readJson(file);
      final payload = _asMap(fixture['payload']);

      test('${_name(file)}: ${fixture['description']}', () {
        // Parses without throwing.
        final batch = EventBatch.fromJson(_asMap(_deepCopy(payload)));

        // Re-serializes to a structure deep-equal to the original payload.
        expect(
          _deepEquals(batch.toJson(), payload),
          isTrue,
          reason: 'round-trip toJson() must deep-equal the fixture payload',
        );
      });
    }
  });

  group('invalid fixtures', () {
    final files = _jsonFiles(Directory('${fixturesDir.path}/invalid'));

    test('directory is present and populated', () {
      expect(files, isNotEmpty, reason: 'no invalid fixtures found');
      expect(files.length, 27);
    });

    for (final file in files) {
      final fixture = _readJson(file);
      final payload = _asMap(fixture['payload']);
      final expectPath = fixture['expect_error_path'] as String?;

      test('${_name(file)}: ${fixture['description']}', () {
        SessionlyProtocolError? caught;
        try {
          EventBatch.fromJson(_asMap(_deepCopy(payload)));
        } on SessionlyProtocolError catch (e) {
          caught = e;
        }
        expect(
          caught,
          isNotNull,
          reason: 'invalid fixture must be rejected with a protocol error',
        );
        if (expectPath != null) {
          expect(
            caught!.path,
            expectPath,
            reason: 'error path should match expect_error_path',
          );
        }
      });
    }
  });
}

Directory _locateFixtures() {
  // Tests run with CWD = package root (sdks/flutter). The fixtures live at the
  // monorepo's packages/core/fixtures.
  final candidates = <String>[
    // Vendored copy in this repo (kept in sync with the upstream monorepo).
    'fixtures',
    '../../packages/core/fixtures',
    'packages/core/fixtures',
  ];
  for (final path in candidates) {
    final dir = Directory(path);
    if (dir.existsSync()) return dir.absolute;
  }
  throw StateError(
    'Could not locate packages/core/fixtures relative to ${Directory.current}',
  );
}

List<File> _jsonFiles(Directory dir) {
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

String _name(File file) => file.uri.pathSegments.last;

Map<String, Object?> _readJson(File file) =>
    _asMap(jsonDecode(file.readAsStringSync()));

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw StateError('expected a JSON object, got ${value.runtimeType}');
}

/// A fresh decoded copy, so a parse cannot alias fixture-owned structures.
Object? _deepCopy(Object? value) => jsonDecode(jsonEncode(value));

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
