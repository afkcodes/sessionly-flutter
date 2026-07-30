/// Shared test doubles for the auto-capture surface tests.
library;

import 'package:sessionly_flutter/sessionly_flutter.dart';

/// A throwaway config for surface tests.
SessionlyConfig testConfig() => SessionlyConfig(
  writeKey: 'sly_w_test',
  endpoint: Uri.parse('https://fp.example.com'),
);

/// One captured emit, flattened for easy assertions.
class Captured {
  Captured(this.type, this.name, this.props, this.screen, this.tsMs);

  final EventType type;
  final String name;
  final Map<String, Object?> props;
  final String? screen;

  /// The explicit capture time the surface passed, or null for "now".
  final int? tsMs;
}

/// A [CaptureSink] that records every emit in order.
class RecordingSink implements CaptureSink {
  final List<Captured> events = <Captured>[];

  Iterable<Captured> named(String name) => events.where((e) => e.name == name);

  @override
  void emit({
    required EventType type,
    required String name,
    Map<String, Object?> props = const {},
    String? screen,
    int? tsMs,
  }) => events.add(Captured(type, name, props, screen, tsMs));
}
