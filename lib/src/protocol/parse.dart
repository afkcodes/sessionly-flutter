/// Internal JSON-reading helpers shared by the protocol `fromJson` factories.
///
/// Every helper throws a [SessionlyProtocolError] carrying the dotted path of
/// the offending field so that failures map onto the fixture
/// `expect_error_path` convention (e.g. `events.0.ctx.os`).
library;

import 'package:sessionly_flutter/src/protocol/errors.dart';

/// Joins a parent [path] and a child [key] into a dotted path segment.
String childPath(String path, String key) => path.isEmpty ? key : '$path.$key';

/// Reads [json] as a JSON object, or throws at [path].
Map<String, Object?> asObject(Object? json, String path) {
  if (json is Map<String, Object?>) return json;
  if (json is Map) return json.cast<String, Object?>();
  throw SessionlyProtocolError('expected an object', path: path);
}

/// Rejects any key in [json] not present in [allowed] (mirrors zod
/// `strictObject`: unknown keys are a protocol violation, not silent extras).
void rejectUnknownKeys(
  Map<String, Object?> json,
  Set<String> allowed,
  String path,
) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw SessionlyProtocolError(
        'unknown key "$key"',
        path: childPath(path, key),
      );
    }
  }
}

/// Reads a required non-empty string field at `path.key`.
String requireString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw SessionlyProtocolError(
      'expected a non-empty string',
      path: childPath(path, key),
    );
  }
  return value;
}

/// Reads a nullable string field (non-empty when present) at `path.key`.
String? requireNullableString(
  Map<String, Object?> json,
  String key,
  String path,
) {
  if (!json.containsKey(key)) {
    throw SessionlyProtocolError('missing field', path: childPath(path, key));
  }
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw SessionlyProtocolError(
      'expected a non-empty string or null',
      path: childPath(path, key),
    );
  }
  return value;
}

/// Reads an optional non-empty string at `path.key`: an absent key yields
/// `null`; a present key must be a non-empty string (mirrors zod `.optional()`,
/// which permits omission but rejects an explicit `null`).
String? optionalString(Map<String, Object?> json, String key, String path) {
  if (!json.containsKey(key)) return null;
  return requireString(json, key, path);
}

/// Reads an optional positive integer at `path.key`: absent → `null`; present
/// must be a positive integer (mirrors zod `.optional()`).
int? optionalPositiveInt(Map<String, Object?> json, String key, String path) {
  if (!json.containsKey(key)) return null;
  return requirePositiveInt(json, key, path);
}

/// Reads an optional enum-like value at `path.key`: absent → `null`; present
/// must be one of [allowed] (mirrors zod `.optional()`).
String? optionalEnum(
  Map<String, Object?> json,
  String key,
  Set<String> allowed,
  String path,
) {
  if (!json.containsKey(key)) return null;
  return requireEnum(json, key, allowed, path);
}

/// Reads a required positive integer field at `path.key`.
int requirePositiveInt(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int || value <= 0) {
    throw SessionlyProtocolError(
      'expected a positive integer',
      path: childPath(path, key),
    );
  }
  return value;
}

/// Reads a required object field at `path.key`.
Map<String, Object?> requireObject(
  Map<String, Object?> json,
  String key,
  String path,
) {
  if (!json.containsKey(key)) {
    throw SessionlyProtocolError('missing field', path: childPath(path, key));
  }
  return asObject(json[key], childPath(path, key));
}

/// Resolves an enum-like value at `path.key` against [allowed] wire values.
String requireEnum(
  Map<String, Object?> json,
  String key,
  Set<String> allowed,
  String path,
) {
  final value = requireString(json, key, path);
  if (!allowed.contains(value)) {
    throw SessionlyProtocolError(
      'must be one of ${allowed.join(', ')}',
      path: childPath(path, key),
    );
  }
  return value;
}
