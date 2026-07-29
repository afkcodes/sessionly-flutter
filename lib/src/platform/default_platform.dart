/// Default [SessionlyPlatform] backed by `path_provider`, `package_info_plus`,
/// and `dart:io`. Runs on the main isolate only; the engine receives its output
/// as a primitive snapshot. Swap it in tests with any fake implementation.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sessionly_flutter/src/platform/sessionly_platform.dart';
import 'package:sessionly_flutter/src/protocol/ctx.dart';

/// Production platform adapter. Every call is async and off the first frame.
class DefaultSessionlyPlatform implements SessionlyPlatform {
  /// Creates the default adapter.
  const DefaultSessionlyPlatform();

  @override
  Future<String> storageDirectory() async {
    final dir = await getApplicationSupportDirectory();
    final sub = Directory('${dir.path}/sessionly');
    if (!sub.existsSync()) sub.createSync(recursive: true);
    return sub.path;
  }

  @override
  Future<CtxSnapshot> snapshot() async {
    final info = await PackageInfo.fromPlatform();
    final view = ui.PlatformDispatcher.instance.implicitView;
    final size = view?.physicalSize ?? ui.Size.zero;
    final ratio = view?.devicePixelRatio ?? 1.0;
    return CtxSnapshot(
      appVersion: info.version.isEmpty ? '0.0.0' : info.version,
      build: info.buildNumber.isEmpty ? null : info.buildNumber,
      os: _os(),
      osVersion: _osVersion(),
      deviceClass: DeviceClass.mid.name,
      locale: _locale(),
      network: NetworkValue.unknown.name,
      screenW: _logical(size.width, ratio),
      screenH: _logical(size.height, ratio),
    );
  }

  static int _logical(double physical, double ratio) {
    final logical = ratio == 0 ? physical : physical / ratio;
    final rounded = logical.round();
    return rounded < 1 ? 1 : rounded;
  }

  static String _os() {
    if (Platform.isAndroid) return OsValue.android.name;
    if (Platform.isIOS) return OsValue.ios.name;
    if (Platform.isMacOS) return OsValue.macos.name;
    if (Platform.isWindows) return OsValue.windows.name;
    return OsValue.linux.name;
  }

  static String _osVersion() {
    final raw = Platform.operatingSystemVersion;
    return raw.isEmpty ? 'unknown' : raw;
  }

  static String _locale() {
    final name = Platform.localeName;
    if (name.isEmpty) return 'en-US';
    // `en_US.UTF-8` -> `en-US`.
    final base = name.split('.').first.replaceAll('_', '-');
    return base.isEmpty ? 'en-US' : base;
  }
}
