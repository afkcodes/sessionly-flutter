/// PII scrub seam (docs/05 privacy). Scrubbing runs in the engine, before disk
/// persistence, so even the local queue is clean. The default masks nothing yet
/// — capture surfaces (P1-T8) are responsible for never capturing input values
/// in the first place; this is the redaction hook for props that do arrive.
library;

/// Transforms an event's `props` before validation and persistence. Must be
/// pure and allocation-conscious; it runs on every event in the engine. It is
/// an interface (not a typedef) because it is the project's PII extension point
/// (Rule 4.10): installing masking must not change any engine signature.
// ignore: one_member_abstracts
abstract interface class Scrubber {
  /// Returns scrubbed props (may return [props] unchanged).
  Map<String, Object?> scrub(String eventName, Map<String, Object?> props);
}

/// The identity scrubber: returns props untouched. The seam exists so a project
/// can install masking without any engine change (Rule 4.10).
class NoopScrubber implements Scrubber {
  /// Creates a [NoopScrubber].
  const NoopScrubber();

  @override
  Map<String, Object?> scrub(String eventName, Map<String, Object?> props) =>
      props;
}
