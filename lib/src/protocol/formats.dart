/// Wire-format primitives: the ISO-8601 timestamp shape, semver, and the id
/// regexes. These mirror `packages/core/src/protocol/v1/formats.ts` and
/// `ids.ts` exactly (Rule 2.1).
library;

import 'package:sessionly_flutter/src/protocol/errors.dart';
import 'package:sessionly_flutter/src/protocol/parse.dart';

/// ISO-8601 UTC timestamp with exactly millisecond precision and a `Z` suffix,
/// e.g. `2026-07-18T10:30:59.821Z`. Offsets are rejected: the SDK always emits
/// UTC and skew correction happens server-side (Rule 2.5).
final RegExp isoDateTimeMsRegex = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);

/// Semver 2.0.0 core subset: `MAJOR.MINOR.PATCH` with optional pre-release and
/// build metadata. Matches `SEMVER_REGEX` in core.
final RegExp semverRegex = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
  r'(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?'
  r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
);

/// UUIDv7 (RFC 9562): 8-4-4-4-12 hex with version nibble `7` and variant nibble
/// `8|9|a|b`. Matches `UUID_V7_REGEX` in core.
final RegExp uuidV7Regex = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Device-scoped `anon_`-prefixed anonymous id. Matches `ANONYMOUS_ID_REGEX`.
final RegExp anonymousIdRegex = RegExp(r'^anon_[A-Za-z0-9_-]+$');

/// `true` iff [value] is a well-formed UUIDv7 string (RFC 9562).
bool isUuidV7(String value) => uuidV7Regex.hasMatch(value);

/// Parses an ISO-8601 millisecond UTC timestamp at [path], or throws.
///
/// The string must match [isoDateTimeMsRegex] before it is parsed, so a
/// non-conforming precision or a non-`Z` offset is rejected up front.
DateTime parseIsoDateTimeMs(String value, String path) {
  if (!isoDateTimeMsRegex.hasMatch(value)) {
    throw SessionlyProtocolError(
      'must be an ISO-8601 UTC timestamp with millisecond precision',
      path: path,
    );
  }
  return DateTime.parse(value).toUtc();
}

/// Formats [instant] as the canonical wire timestamp (millisecond precision,
/// `Z` suffix), independent of the platform's `toIso8601String` behaviour.
String formatIsoDateTimeMs(DateTime instant) {
  final utc = instant.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final year = utc.year.toString().padLeft(4, '0');
  final ms = utc.millisecond.toString().padLeft(3, '0');
  return '$year-${two(utc.month)}-${two(utc.day)}'
      'T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}.${ms}Z';
}

/// Validates that the string at `path.key` is a UUIDv7, returning it.
String requireUuidV7(Map<String, Object?> json, String key, String path) {
  final value = requireString(json, key, path);
  if (!isUuidV7(value)) {
    throw SessionlyProtocolError(
      'must be a UUIDv7 (version nibble 7, RFC 9562 variant)',
      path: childPath(path, key),
    );
  }
  return value;
}

/// Validates that the string at `path.key` is an `anon_`-prefixed id.
String requireAnonymousId(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = requireString(json, key, path);
  if (!anonymousIdRegex.hasMatch(value)) {
    throw SessionlyProtocolError(
      'anonymous_id must be `anon_`-prefixed',
      path: childPath(path, key),
    );
  }
  return value;
}

/// Validates that the string at `path.key` is a semver string.
String requireSemver(Map<String, Object?> json, String key, String path) {
  final value = requireString(json, key, path);
  if (!semverRegex.hasMatch(value)) {
    throw SessionlyProtocolError(
      'must be a semver string (MAJOR.MINOR.PATCH)',
      path: childPath(path, key),
    );
  }
  return value;
}
