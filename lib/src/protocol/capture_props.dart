/// Typed-prop validation for the additive capture surfaces, mirroring
/// `packages/core/src/protocol/v1/capture-props.ts` exactly (Rule 2.1).
///
/// Like `validateRevenueProps`, these props are validated on the wire, keyed on
/// event `name`: coordinates (`auto/tap`, `frustration/rage_tap|dead_tap`),
/// `perf/http_slow`, `auto/scroll_depth`, and `auto/input_focus|input_abandon`.
/// The generic shape/size caps are enforced separately by `validateProps`; this
/// pins only the surface-specific fields. Additive-only (Rule 2.3): optional
/// fields are validated only when present, so the web SDK's already-shipped
/// shapes stay valid.
library;

import 'package:sessionly_flutter/src/protocol/errors.dart';
import 'package:sessionly_flutter/src/protocol/parse.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

/// HTTP methods a `perf/http_slow` sample may carry (bounded, additive-only).
const Set<String> httpMethods = {
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'OTHER',
};

/// Upper bound on an HTTP status code. `0` denotes a network failure.
const int httpStatusMax = 599;

/// Scroll-depth buckets — the SAME contract the web SDK emits (docs/05).
const Set<int> scrollDepthBuckets = {25, 50, 75, 100};

/// Upper bound on a `flag_exposure` value digest (chars). Mirrors
/// `FLAG_VALUE_DIGEST_MAX` in `packages/core` — never the raw flag payload.
const int flagValueDigestMax = 128;

/// Upper bound on an `experiment_exposure` variant name (chars). Mirrors
/// `EXPERIMENT_VARIANT_MAX` in `packages/core`.
const int experimentVariantMax = 128;

/// Validates the typed props for [type]/[name] at [path] (the props object's
/// dotted path), throwing a [SessionlyProtocolError] at the offending child on
/// any violation. A no-op for names without a typed contract.
void validateCaptureProps(
  EventType type,
  String name,
  Map<String, Object?> props,
  String path,
) {
  if (type == EventType.auto && name == 'tap') {
    _validateCoords(props, path);
  } else if (type == EventType.frustration &&
      (name == 'rage_tap' || name == 'dead_tap')) {
    _validateCoords(props, path);
  } else if (type == EventType.perf && name == 'http_slow') {
    _validateHttpSlow(props, path);
  } else if (type == EventType.auto && name == 'scroll_depth') {
    _validateScrollDepth(props, path);
  } else if (type == EventType.auto && name == 'input_focus') {
    requireString(props, 'field', path);
  } else if (type == EventType.auto && name == 'input_abandon') {
    _validateInputAbandon(props, path);
  } else if (type == EventType.auto && name == 'flag_exposure') {
    _validateFlagExposure(props, path);
  } else if (type == EventType.auto && name == 'experiment_exposure') {
    _validateExperimentExposure(props, path);
  }
}

void _validateExperimentExposure(Map<String, Object?> props, String path) {
  requireString(props, 'key', path);
  final variant = requireString(props, 'variant', path);
  if (variant.length > experimentVariantMax) {
    throw SessionlyProtocolError(
      'variant must be at most $experimentVariantMax characters',
      path: childPath(path, 'variant'),
    );
  }
}

void _validateFlagExposure(Map<String, Object?> props, String path) {
  requireString(props, 'key', path);
  if (props['enabled'] is! bool) {
    throw SessionlyProtocolError(
      'enabled must be a boolean',
      path: childPath(path, 'enabled'),
    );
  }
  if (props.containsKey('value')) {
    final value = requireString(props, 'value', path);
    if (value.length > flagValueDigestMax) {
      throw SessionlyProtocolError(
        'value digest must be at most $flagValueDigestMax characters',
        path: childPath(path, 'value'),
      );
    }
  }
}

void _validateCoords(Map<String, Object?> props, String path) {
  _optionalUnitFraction(props, 'x', path);
  _optionalUnitFraction(props, 'y', path);
}

void _validateHttpSlow(Map<String, Object?> props, String path) {
  requireEnum(props, 'method', httpMethods, path);
  _requireIntInRange(props, 'status', 0, httpStatusMax, path);
  _requireNonNegativeInt(props, 'duration_ms', path);

  // host (optional): a bare authority — no credentials (@) or path (/).
  if (props.containsKey('host')) {
    final host = requireString(props, 'host', path);
    if (host.contains('@') || host.contains('/')) {
      throw SessionlyProtocolError(
        'host must be a bare authority — no credentials (@) or path (/)',
        path: childPath(path, 'host'),
      );
    }
  }

  // path (optional): a path ONLY — leading /, never a query (?) or fragment (#).
  if (props.containsKey('path')) {
    final p = requireString(props, 'path', path);
    if (!p.startsWith('/') || p.contains('?') || p.contains('#')) {
      throw SessionlyProtocolError(
        'path must start with / and carry no query string (?) or fragment (#)',
        path: childPath(path, 'path'),
      );
    }
  }

  if (props.containsKey('threshold_ms')) {
    _requireNonNegativeInt(props, 'threshold_ms', path);
  }
}

void _validateScrollDepth(Map<String, Object?> props, String path) {
  final value = props['depth_pct'];
  if (value is! int || !scrollDepthBuckets.contains(value)) {
    throw SessionlyProtocolError(
      'depth_pct must be one of ${scrollDepthBuckets.join(', ')}',
      path: childPath(path, 'depth_pct'),
    );
  }
}

void _validateInputAbandon(Map<String, Object?> props, String path) {
  requireString(props, 'field', path);
  if (props.containsKey('dwell_ms')) {
    _requireNonNegativeInt(props, 'dwell_ms', path);
  }
  if (props.containsKey('had_input') && props['had_input'] is! bool) {
    throw SessionlyProtocolError(
      'had_input must be a boolean',
      path: childPath(path, 'had_input'),
    );
  }
}

/// Validates an optional normalized coordinate: absent → ok; present must be a
/// number in [0, 1] (mirrors zod `z.number().min(0).max(1).optional()`).
void _optionalUnitFraction(
  Map<String, Object?> props,
  String key,
  String path,
) {
  if (!props.containsKey(key)) return;
  final value = props[key];
  if (value is! num || value < 0 || value > 1) {
    throw SessionlyProtocolError(
      '$key must be a number in [0, 1]',
      path: childPath(path, key),
    );
  }
}

void _requireIntInRange(
  Map<String, Object?> props,
  String key,
  int min,
  int max,
  String path,
) {
  final value = props[key];
  if (value is! int || value < min || value > max) {
    throw SessionlyProtocolError(
      '$key must be an integer in [$min, $max]',
      path: childPath(path, key),
    );
  }
}

void _requireNonNegativeInt(
  Map<String, Object?> props,
  String key,
  String path,
) {
  final value = props[key];
  if (value is! int || value < 0) {
    throw SessionlyProtocolError(
      '$key must be a non-negative integer',
      path: childPath(path, key),
    );
  }
}
