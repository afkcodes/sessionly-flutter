/// `props` limits, mirroring `packages/core/src/protocol/v1/limits.ts`: values
/// are scalars or shallow objects (depth ≤ 2); at most [propsMaxKeys] keys;
/// total serialized size ≤ [propsMaxBytes]. These bound per-event cost on the
/// ingest hot path and keep the ClickHouse JSON column sane.
library;

import 'dart:convert';

import 'package:sessionly_flutter/src/protocol/errors.dart';

/// Maximum number of top-level `props` keys.
const int propsMaxKeys = 40;

/// Maximum `props` nesting depth (a value may be a scalar/array, or a single
/// object of scalars/arrays).
const int propsMaxDepth = 2;

/// Maximum serialized (`utf8`) `props` size in bytes.
const int propsMaxBytes = 16 * 1024;

/// The outcome of validating a `props` map.
///
/// The engine uses this to reject over-budget props cheaply before enqueue,
/// without throwing (Rule 0.3); the event `fromJson` factories convert a
/// failure into a typed [SessionlyProtocolError].
class PropsValidation {
  const PropsValidation._(this.isValid, this.reason);

  /// A failed validation carrying a human-readable [reason].
  factory PropsValidation.invalid(String reason) =>
      PropsValidation._(false, reason);

  /// A successful validation.
  static const PropsValidation valid = PropsValidation._(true, null);

  /// `true` iff the props conform to every limit.
  final bool isValid;

  /// Human-readable failure reason, or `null` when [isValid].
  final String? reason;
}

bool _isScalar(Object? value) =>
    value == null || value is String || value is num || value is bool;

bool _isLeaf(Object? value) {
  if (_isScalar(value)) return true;
  if (value is List) return value.every(_isScalar);
  return false;
}

/// A top-level prop value: a leaf (scalar / array of scalars), or a single
/// object whose values are all leaves (→ overall depth ≤ 2).
bool _isPropValue(Object? value) {
  if (_isLeaf(value)) return true;
  if (value is Map) {
    return value.keys.every((k) => k is String) && value.values.every(_isLeaf);
  }
  return false;
}

/// Validates a decoded `props` map against the shape, key-count, and size
/// limits. Returns a typed [PropsValidation] rather than throwing.
PropsValidation validateProps(Map<String, Object?> props) {
  for (final entry in props.entries) {
    if (!_isPropValue(entry.value)) {
      return PropsValidation.invalid(
        'prop "${entry.key}" exceeds depth $propsMaxDepth or is not a '
        'permitted scalar/array/object shape',
      );
    }
  }
  if (props.length > propsMaxKeys) {
    return PropsValidation.invalid('props may not exceed $propsMaxKeys keys');
  }
  final bytes = utf8.encode(jsonEncode(props)).length;
  if (bytes > propsMaxBytes) {
    return PropsValidation.invalid(
      'props serialized size may not exceed $propsMaxBytes bytes',
    );
  }
  return PropsValidation.valid;
}

/// Reads and validates the `props` map at [path], throwing on any violation.
Map<String, Object?> requireProps(Object? value, String path) {
  if (value is! Map) {
    throw SessionlyProtocolError('expected an object', path: path);
  }
  final props = value.cast<String, Object?>();
  final result = validateProps(props);
  if (!result.isValid) {
    throw SessionlyProtocolError(result.reason!, path: path);
  }
  return props;
}
