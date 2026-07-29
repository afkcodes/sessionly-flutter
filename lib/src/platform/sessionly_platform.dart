/// Platform adapter seam.
///
/// The engine runs in a plain Dart isolate and must not touch Flutter plugins.
/// Everything platform-specific (paths, package info, device metadata) is
/// gathered on the main isolate by a [SessionlyPlatform] and handed to the
/// engine as a primitive [CtxSnapshot] over the `SendPort`.
library;

import 'package:sessionly_flutter/src/protocol/ctx.dart';

/// Immutable, port-transferable snapshot of device/app context. Mirrors
/// [EventCtx] but carries only primitives so it crosses an isolate boundary
/// without an expensive copy.
class CtxSnapshot {
  /// Creates a [CtxSnapshot].
  const CtxSnapshot({
    required this.appVersion,
    required this.build,
    required this.os,
    required this.osVersion,
    required this.deviceClass,
    required this.locale,
    required this.network,
    required this.screenW,
    required this.screenH,
  });

  /// Rebuilds a snapshot from its port-transferable map form.
  factory CtxSnapshot.fromMap(Map<String, Object?> map) => CtxSnapshot(
    appVersion: map['app_version']! as String,
    build: map['build'] as String?,
    os: map['os']! as String,
    osVersion: map['os_version']! as String,
    deviceClass: map['device_class']! as String,
    locale: map['locale']! as String,
    network: map['network']! as String,
    screenW: map['screen_w']! as int,
    screenH: map['screen_h']! as int,
  );

  /// App version, e.g. `1.4.2`.
  final String appVersion;

  /// Build number, or `null`.
  final String? build;

  /// OS wire value (see [OsValue]).
  final String os;

  /// OS version string.
  final String osVersion;

  /// Bucketed device class (see [DeviceClass]).
  final String deviceClass;

  /// BCP-47 locale.
  final String locale;

  /// Coarse network wire value (see [NetworkValue]).
  final String network;

  /// Logical screen width.
  final int screenW;

  /// Logical screen height.
  final int screenH;

  /// The port-transferable primitive form.
  Map<String, Object?> toMap() => {
    'app_version': appVersion,
    'build': build,
    'os': os,
    'os_version': osVersion,
    'device_class': deviceClass,
    'locale': locale,
    'network': network,
    'screen_w': screenW,
    'screen_h': screenH,
  };

  /// Materializes the protocol [EventCtx] used on every event.
  EventCtx toCtx() => EventCtx(
    appVersion: appVersion,
    build: build,
    os: os,
    osVersion: osVersion,
    deviceClass: deviceClass,
    locale: locale,
    network: network,
    screenW: screenW,
    screenH: screenH,
  );
}

/// Provides platform facts the engine cannot compute for itself. Fully
/// injectable so engine tests never need a device.
abstract interface class SessionlyPlatform {
  /// Absolute directory the engine may use for its sqlite queue. Resolved off
  /// the first frame (async), never a synchronous main-thread call.
  Future<String> storageDirectory();

  /// A one-shot context snapshot for `ctx` assembly, gathered at init.
  Future<CtxSnapshot> snapshot();
}
