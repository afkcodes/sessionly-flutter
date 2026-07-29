/// Device / app context attached to every event, mirroring
/// `packages/core/src/protocol/v1/ctx.ts`. Enums are intentionally coarse
/// (bucketed `device_class`, not fingerprinting). The shape is closed: unknown
/// keys are a protocol violation, and new fields arrive additively (Rule 2.3).
///
/// The web SDK contributes additive OPTIONAL fields (docs/05): `browser`,
/// `browser_version`, `viewport_w/h`, `connection`. On the wire they are
/// absent-or-value (never explicit `null`) — matching the TS `.optional()`
/// fields — so `toJson` emits each only when present, and a payload omitting
/// them round-trips byte-identically. The Flutter SDK never produces them; this
/// mirror parses them because web batches share the protocol.
library;

import 'package:sessionly_flutter/src/protocol/parse.dart';

/// Operating-system platform bucket.
enum OsValue {
  /// Android.
  android,

  /// iOS.
  ios,

  /// Web.
  web,

  /// Windows.
  windows,

  /// macOS.
  macos,

  /// Linux.
  linux;

  /// Permitted wire values, in schema order.
  static const Set<String> wireValues = {
    'android',
    'ios',
    'web',
    'windows',
    'macos',
    'linux',
  };
}

/// Bucketed device performance class.
enum DeviceClass {
  /// Low-end device.
  low,

  /// Mid-range device.
  mid,

  /// High-end device.
  high;

  /// Permitted wire values, in schema order.
  static const Set<String> wireValues = {'low', 'mid', 'high'};
}

/// Coarse network connection type.
enum NetworkValue {
  /// Wi-Fi.
  wifi,

  /// Cellular.
  cellular,

  /// Ethernet.
  ethernet,

  /// Known to be offline.
  offline,

  /// Unknown / undeterminable.
  unknown;

  /// Permitted wire values, in schema order.
  static const Set<String> wireValues = {
    'wifi',
    'cellular',
    'ethernet',
    'offline',
    'unknown',
  };
}

/// Effective connection type — the Network Information API `effectiveType`
/// values plus `unknown` (docs/05). Distinct from [NetworkValue]: `connection`
/// is the web-measured effective quality, not the transport bucket.
enum ConnectionValue {
  /// Effective `slow-2g`.
  slow2g,

  /// Effective `2g`.
  twoG,

  /// Effective `3g`.
  threeG,

  /// Effective `4g`.
  fourG,

  /// Unknown / undeterminable.
  unknown;

  /// Permitted wire values, in schema order.
  static const Set<String> wireValues = {
    'slow-2g',
    '2g',
    '3g',
    '4g',
    'unknown',
  };
}

/// The closed set of `ctx` keys accepted on the wire. The final five are the
/// web additive optional fields (docs/05).
const Set<String> _ctxKeys = {
  'app_version',
  'build',
  'os',
  'os_version',
  'device_class',
  'locale',
  'network',
  'screen_w',
  'screen_h',
  'browser',
  'browser_version',
  'viewport_w',
  'viewport_h',
  'connection',
};

/// Device / app context for a single event.
class EventCtx {
  /// Creates an [EventCtx]. The five `browser`/`viewport`/`connection` fields
  /// are web-only additive optionals; omit them (default `null`) off web.
  const EventCtx({
    required this.appVersion,
    required this.build,
    required this.os,
    required this.osVersion,
    required this.deviceClass,
    required this.locale,
    required this.network,
    required this.screenW,
    required this.screenH,
    this.browser,
    this.browserVersion,
    this.viewportW,
    this.viewportH,
    this.connection,
  });

  /// Parses an [EventCtx] from a decoded JSON map, throwing
  /// `SessionlyProtocolError` at [path] on any violation.
  factory EventCtx.fromJson(
    Map<String, Object?> json, {
    String path = 'ctx',
  }) {
    rejectUnknownKeys(json, _ctxKeys, path);
    return EventCtx(
      appVersion: requireString(json, 'app_version', path),
      build: requireNullableString(json, 'build', path),
      os: requireEnum(json, 'os', OsValue.wireValues, path),
      osVersion: requireString(json, 'os_version', path),
      deviceClass: requireEnum(
        json,
        'device_class',
        DeviceClass.wireValues,
        path,
      ),
      locale: requireString(json, 'locale', path),
      network: requireEnum(json, 'network', NetworkValue.wireValues, path),
      screenW: requirePositiveInt(json, 'screen_w', path),
      screenH: requirePositiveInt(json, 'screen_h', path),
      browser: optionalString(json, 'browser', path),
      browserVersion: optionalString(json, 'browser_version', path),
      viewportW: optionalPositiveInt(json, 'viewport_w', path),
      viewportH: optionalPositiveInt(json, 'viewport_h', path),
      connection: optionalEnum(
        json,
        'connection',
        ConnectionValue.wireValues,
        path,
      ),
    );
  }

  /// App version string, e.g. `2.3.1`.
  final String appVersion;

  /// Build identifier, or `null`.
  final String? build;

  /// Operating-system platform (wire value).
  final String os;

  /// Operating-system version string.
  final String osVersion;

  /// Bucketed device class (wire value).
  final String deviceClass;

  /// BCP-47 language tag, e.g. `en-IN`.
  final String locale;

  /// Coarse network type (wire value).
  final String network;

  /// Logical screen width in pixels.
  final int screenW;

  /// Logical screen height in pixels.
  final int screenH;

  /// Browser engine/name, e.g. `chrome` (web only), or `null`.
  final String? browser;

  /// Browser version string (web only), or `null`.
  final String? browserVersion;

  /// CSS viewport width in pixels (web only), or `null`.
  final int? viewportW;

  /// CSS viewport height in pixels (web only), or `null`.
  final int? viewportH;

  /// Effective connection type (web only, [ConnectionValue.wireValues]), or
  /// `null`.
  final String? connection;

  /// Serializes to the exact wire shape (snake_case keys, `null` preserved for
  /// the always-present nullable `build`). The web additive optionals are
  /// emitted only when non-null (absent-or-value on the wire), so a payload
  /// without them round-trips byte-identically (Rule 2.3).
  Map<String, Object?> toJson() => {
    'app_version': appVersion,
    'build': build,
    'os': os,
    'os_version': osVersion,
    'device_class': deviceClass,
    'locale': locale,
    'network': network,
    'screen_w': screenW,
    'screen_h': screenH,
    if (browser != null) 'browser': browser,
    if (browserVersion != null) 'browser_version': browserVersion,
    if (viewportW != null) 'viewport_w': viewportW,
    if (viewportH != null) 'viewport_h': viewportH,
    if (connection != null) 'connection': connection,
  };
}
