import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

import 'support.dart';

SessionlyConfig config({bool captureMessages = false}) => SessionlyConfig(
  writeKey: 'sly_w_test',
  endpoint: Uri.parse('https://fp.example.com'),
  captureErrorMessages: captureMessages,
);

void main() {
  late RecordingSink sink;
  late FlutterExceptionHandler? savedFlutter;
  late bool Function(Object, StackTrace)? savedPlatform;

  setUp(() {
    sink = RecordingSink();
    savedFlutter = FlutterError.onError;
    savedPlatform = PlatformDispatcher.instance.onError;
    // Benign defaults so chaining does not reach the test harness's
    // failure-reporting handler. Individual tests override as needed.
    FlutterError.onError = (_) {};
    PlatformDispatcher.instance.onError = (_, _) => true;
  });

  tearDown(() {
    FlutterError.onError = savedFlutter;
    PlatformDispatcher.instance.onError = savedPlatform;
  });

  test('FlutterError chain calls the previous handler and emits', () {
    var prevCalled = false;
    FlutterError.onError = (_) => prevCalled = true;
    final handlers = SessionlyErrorHandlers(sink: sink, config: config())
      ..install();

    FlutterError.onError!(
      FlutterErrorDetails(
        exception: StateError('boom'),
        stack: StackTrace.current,
      ),
    );
    handlers.uninstall();

    expect(prevCalled, isTrue, reason: 'previous handler must still run');
    final err = sink.named('flutter_error').single;
    expect(err.type, EventType.error);
    expect(err.props['fatal'], false);
    expect(err.props['error_type'], 'StateError');
  });

  test('PlatformDispatcher chain calls previous and emits a fatal crash', () {
    var prevCalled = false;
    PlatformDispatcher.instance.onError = (_, _) {
      prevCalled = true;
      return true;
    };
    final handlers = SessionlyErrorHandlers(sink: sink, config: config())
      ..install();

    final handled = PlatformDispatcher.instance.onError!(
      ArgumentError('bad'),
      StackTrace.current,
    );
    handlers.uninstall();

    expect(prevCalled, isTrue);
    expect(handled, isTrue, reason: 'chain propagates the prev return value');
    final crash = sink.named('crash').single;
    expect(crash.props['fatal'], true);
  });

  test('message excluded by default; hash present and stable', () {
    final handlers = SessionlyErrorHandlers(sink: sink, config: config())
      ..install();
    void raise() => FlutterError.onError!(
      FlutterErrorDetails(exception: StateError('secret value 42')),
    );
    raise();
    raise();
    handlers.uninstall();

    final events = sink.named('flutter_error').toList();
    expect(events, hasLength(2));
    for (final e in events) {
      expect(e.props.containsKey('message'), isFalse);
      expect(e.props['message_hash'], isA<String>());
    }
    expect(events[0].props['message_hash'], events[1].props['message_hash']);
  });

  test('opt-in sanitized message is included when configured', () {
    final handlers = SessionlyErrorHandlers(
      sink: sink,
      config: config(captureMessages: true),
    )..install();
    FlutterError.onError!(
      FlutterErrorDetails(exception: StateError('multi\nline  message')),
    );
    handlers.uninstall();

    final msg = sink.named('flutter_error').single.props['message']! as String;
    expect(msg, isNot(contains('\n')));
  });

  test('stack digest keeps at most 5 frames, no absolute paths', () {
    final handlers = SessionlyErrorHandlers(sink: sink, config: config())
      ..install();
    final trace = StackTrace.fromString(
      List.generate(
        12,
        (i) => '#$i      Foo.bar$i (package:app/x.dart:$i:2)',
      ).join('\n'),
    );
    FlutterError.onError!(
      FlutterErrorDetails(exception: StateError('x'), stack: trace),
    );
    handlers.uninstall();

    final digest =
        sink.named('flutter_error').single.props['stack_digest']! as String;
    expect(digest.split('|'), hasLength(5));
    expect(digest, isNot(contains('/home/')));
  });
}
