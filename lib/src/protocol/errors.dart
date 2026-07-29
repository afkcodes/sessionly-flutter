/// Raised when a value does not conform to wire protocol v1.
///
/// This is the SDK's single typed protocol failure. Model constructors and
/// `fromJson` factories throw it (and nothing else) on malformed input; the
/// engine catches it at the public-API boundary so it never escapes into the
/// host app (Rule 0.3). Serializers of already-validated models never throw.
class SessionlyProtocolError implements Exception {
  /// Creates a protocol error with a human-readable [message] and an optional
  /// [path] identifying the offending field (e.g. `events.0.ctx.os`), matching
  /// the `expect_error_path` convention of the shared fixtures.
  const SessionlyProtocolError(this.message, {this.path});

  /// Human-readable description of the violation.
  final String message;

  /// Dotted path to the offending field, or `null` for root-level errors.
  final String? path;

  @override
  String toString() => 'SessionlyProtocolError(${path ?? '<root>'}): $message';
}
