/// Deterministic in-SDK experiment assignment (docs/10 Suite modules). Given a
/// stable per-actor seed (the anonymous id), an experiment key, and its
/// delivered variants (`[{name, weight, value?}]`), picks one variant by
/// `hash(seed:key) mod totalWeight` walked against cumulative weights.
///
/// The mapping is PURE and STABLE: the same (seed, key, variant set) always
/// resolves to the same variant, so assignment is sticky per actor with no
/// stored state (Rule 0.1 O(1); never throws — a malformed variant set yields
/// null and the caller assigns nothing). There is NO bespoke A/B engine here —
/// exposure is an ordinary event, readouts are ordinary funnels/segments.
library;

/// One resolved assignment: the chosen variant [name] and its optional
/// structured [value] (delivered alongside the flag).
class ExperimentAssignment {
  /// Creates an assignment.
  const ExperimentAssignment({required this.name, this.value});

  /// The chosen variant name.
  final String name;

  /// The chosen variant's structured value, or null for a bare variant.
  final Object? value;
}

/// 32-bit FNV-1a over the UTF-16 code units of [input]. A small,
/// dependency-free stable hash — identical across runs and platforms so
/// bucketing is deterministic.
int _fnv1a32(String input) {
  var hash = 0x811c9dc5;
  for (var i = 0; i < input.length; i++) {
    hash ^= input.codeUnitAt(i) & 0xff;
    // 32-bit FNV prime multiply, masked to stay in range on all platforms.
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// Resolves the variant for [seed]/[key] over [variants], or null when no
/// assignment is possible (empty/malformed set, non-positive total weight).
/// Never throws — every branch degrades to null.
ExperimentAssignment? assignExperimentVariant(
  String seed,
  String key,
  List<Object?> variants,
) {
  // Collect valid variants and the total weight in one pass. A variant must be
  // a map with a non-empty string name and a positive integer-ish weight.
  final names = <String>[];
  final weights = <int>[];
  final values = <Object?>[];
  var total = 0;
  for (final raw in variants) {
    if (raw is! Map) continue;
    final name = raw['name'];
    final weight = raw['weight'];
    if (name is! String || name.isEmpty) continue;
    if (weight is! num || weight <= 0) continue;
    final w = weight.floor();
    if (w <= 0) continue;
    names.add(name);
    weights.add(w);
    values.add(raw['value']);
    total += w;
  }
  if (total <= 0 || names.isEmpty) return null;

  final bucket = _fnv1a32('$seed:$key') % total;
  var cumulative = 0;
  for (var i = 0; i < names.length; i++) {
    cumulative += weights[i];
    if (bucket < cumulative) {
      return ExperimentAssignment(name: names[i], value: values[i]);
    }
  }
  // Unreachable when total > 0, but stay total (never throw): last variant.
  return ExperimentAssignment(name: names.last, value: values.last);
}
