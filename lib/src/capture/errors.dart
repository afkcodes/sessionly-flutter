/// Error capture. Chains — never replaces — `FlutterError.onError` and
/// `PlatformDispatcher.onError` (docs/05): the previous handler is stored and
/// always invoked, so we sit transparently in front of Crashlytics/Sentry/etc.
///
/// PII: the raw exception message is never sent by default — only a stable hash
/// plus a package-filtered digest of the top frames. A sanitized message is
/// included only when [SessionlyConfig.captureErrorMessages] is set.
library;

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:sessionly_flutter/src/capture/capture_sink.dart';
import 'package:sessionly_flutter/src/config.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

/// Installs and later restores the chained global error handlers.
class SessionlyErrorHandlers {
  /// Emits through [sink]; honors [config] for message inclusion. [nowScreen]
  /// supplies the current screen at throw time.
  SessionlyErrorHandlers({
    required CaptureSink sink,
    required SessionlyConfig config,
    String? Function()? nowScreen,
  }) : _sink = sink,
       _config = config,
       _nowScreen = nowScreen ?? (() => null);

  final CaptureSink _sink;
  final SessionlyConfig _config;
  final String? Function() _nowScreen;

  FlutterExceptionHandler? _prevFlutterOnError;
  bool _hadPrevFlutter = false;
  ErrorCallback? _prevPlatformOnError;
  bool _installed = false;

  /// Chains onto the current handlers. Idempotent.
  void install() {
    if (_installed) return;
    _installed = true;
    _prevFlutterOnError = FlutterError.onError;
    _hadPrevFlutter = _prevFlutterOnError != null;
    FlutterError.onError = _onFlutterError;
    _prevPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = _onPlatformError;
  }

  /// Restores whatever handlers were installed before [install].
  void uninstall() {
    if (!_installed) return;
    _installed = false;
    FlutterError.onError = _prevFlutterOnError;
    PlatformDispatcher.instance.onError = _prevPlatformOnError;
  }

  void _onFlutterError(FlutterErrorDetails details) {
    _record(
      name: 'flutter_error',
      error: details.exception,
      stack: details.stack,
      fatal: false,
    );
    // Always call the previous handler (never silently replaced).
    if (_hadPrevFlutter) {
      _prevFlutterOnError!(details);
    } else {
      FlutterError.presentError(details);
    }
  }

  bool _onPlatformError(Object error, StackTrace stack) {
    _record(name: 'crash', error: error, stack: stack, fatal: true);
    return _prevPlatformOnError?.call(error, stack) ?? false;
  }

  void _record({
    required String name,
    required Object error,
    required StackTrace? stack,
    required bool fatal,
  }) {
    final message = error.toString();
    final props = <String, Object?>{
      'error_type': error.runtimeType.toString(),
      'message_hash': _fnv1aHex(message),
      'stack_digest': _stackDigest(stack),
      'fatal': fatal,
    };
    if (_config.captureErrorMessages) {
      props['message'] = _sanitizeMessage(message);
    }
    _sink.emit(
      type: EventType.error,
      name: name,
      props: props,
      screen: _nowScreen(),
    );
  }
}

/// Stable 32-bit FNV-1a hex of [input] — lets the backend group identical
/// errors without ever seeing their text.
String _fnv1aHex(String input) {
  var hash = 0x811c9dc5;
  for (var i = 0; i < input.length; i++) {
    hash ^= input.codeUnitAt(i) & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Clamped, newline-stripped message for the opt-in path.
String _sanitizeMessage(String message) {
  final flat = message.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= 256 ? flat : flat.substring(0, 256);
}

/// Top-5 stack frames, package-filtered: member symbol plus a redacted
/// location (absolute filesystem paths removed — a PII risk).
String _stackDigest(StackTrace? stack) {
  if (stack == null) return '';
  final frames = <String>[];
  for (final raw in stack.toString().split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    frames.add(_sanitizeFrame(line));
    if (frames.length >= 5) break;
  }
  return frames.join('|');
}

String _sanitizeFrame(String frame) {
  // Standard trace: "#0      Type.member (package:app/x.dart:1:2)".
  final open = frame.indexOf('(');
  final member = (open >= 0 ? frame.substring(0, open) : frame)
      .replaceFirst(RegExp(r'^#\d+\s*'), '')
      .trim();
  if (open < 0) return member;
  final close = frame.indexOf(')', open);
  final uri = frame.substring(open + 1, close < 0 ? frame.length : close);
  final safeUri = uri.startsWith('package:') || uri.startsWith('dart:')
      ? uri
      : '<redacted>';
  return '$member ($safeUri)';
}
