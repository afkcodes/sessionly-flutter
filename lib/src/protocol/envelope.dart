/// The `POST /v1/events` request envelope, mirroring
/// `packages/core/src/protocol/v1/envelope.ts`. `sent_at` supports clock-skew
/// correction against the server `received_at` (Rule 2.5).
library;

import 'package:sessionly_flutter/src/protocol/errors.dart';
import 'package:sessionly_flutter/src/protocol/event.dart';
import 'package:sessionly_flutter/src/protocol/formats.dart';
import 'package:sessionly_flutter/src/protocol/parse.dart';

/// Wire protocol version implemented by this module.
const int protocolVersion = 1;

/// Minimum events per batch.
const int batchMinEvents = 1;

/// Maximum events per batch.
const int batchMaxEvents = 500;

/// Permitted `sdk.name` values.
const Set<String> sdkNames = {
  'sessionly-flutter',
  'sessionly-web',
  'sessionly-server',
};

/// The name this SDK reports on the wire.
const String flutterSdkName = 'sessionly-flutter';

const Set<String> _sdkKeys = {'name', 'version'};
const Set<String> _batchKeys = {'protocol', 'sent_at', 'sdk', 'events'};

/// Identifies the SDK that produced a batch.
class SdkInfo {
  /// Creates an [SdkInfo].
  const SdkInfo({required this.name, required this.version});

  /// Parses [SdkInfo] from JSON at [path].
  factory SdkInfo.fromJson(Map<String, Object?> json, {String path = 'sdk'}) {
    rejectUnknownKeys(json, _sdkKeys, path);
    return SdkInfo(
      name: requireEnum(json, 'name', sdkNames, path),
      version: requireSemver(json, 'version', path),
    );
  }

  /// SDK name (one of [sdkNames]).
  final String name;

  /// SDK semver.
  final String version;

  /// Serializes to the wire shape.
  Map<String, Object?> toJson() => {'name': name, 'version': version};
}

/// The full `POST /v1/events` request body: protocol version, send time, SDK
/// info, and 1..500 events.
class EventBatch {
  /// Creates an [EventBatch].
  const EventBatch({
    required this.sentAt,
    required this.sdk,
    required this.events,
  });

  /// Parses an [EventBatch] from a decoded JSON map, throwing
  /// [SessionlyProtocolError] (with a fixture-aligned `path`) on any violation.
  factory EventBatch.fromJson(Map<String, Object?> json) {
    rejectUnknownKeys(json, _batchKeys, '');
    final protocol = json['protocol'];
    if (protocol != protocolVersion) {
      throw const SessionlyProtocolError(
        'protocol must be $protocolVersion',
        path: 'protocol',
      );
    }
    final sentAtRaw = requireString(json, 'sent_at', '');
    final sentAt = parseIsoDateTimeMs(sentAtRaw, 'sent_at');
    final sdk = SdkInfo.fromJson(requireObject(json, 'sdk', ''));
    final rawEvents = json['events'];
    if (rawEvents is! List) {
      throw const SessionlyProtocolError('expected an array', path: 'events');
    }
    if (rawEvents.length < batchMinEvents ||
        rawEvents.length > batchMaxEvents) {
      throw const SessionlyProtocolError(
        'batch must carry $batchMinEvents..$batchMaxEvents events',
        path: 'events',
      );
    }
    final events = <SessionlyEvent>[];
    for (var i = 0; i < rawEvents.length; i++) {
      events.add(
        SessionlyEvent.fromJson(
          asObject(rawEvents[i], 'events.$i'),
          path: 'events.$i',
        ),
      );
    }
    return EventBatch(sentAt: sentAt, sdk: sdk, events: events);
  }

  /// Time the batch was sent (UTC).
  final DateTime sentAt;

  /// SDK identity.
  final SdkInfo sdk;

  /// The events carried by this batch (1..500).
  final List<SessionlyEvent> events;

  /// The protocol version (always [protocolVersion]).
  int get protocol => protocolVersion;

  /// Serializes to the exact `POST /v1/events` wire shape.
  Map<String, Object?> toJson() => {
    'protocol': protocolVersion,
    'sent_at': formatIsoDateTimeMs(sentAt),
    'sdk': sdk.toJson(),
    'events': events.map((e) => e.toJson()).toList(),
  };
}
