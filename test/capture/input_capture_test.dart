import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

import 'support.dart';

void main() {
  late RecordingSink sink;
  late CurrentScreenTracker tracker;
  late int now;

  setUp(() {
    sink = RecordingSink();
    tracker = CurrentScreenTracker()..update('Form');
    now = 1000;
  });

  Future<InputFocusCapture> pumpForm(
    WidgetTester tester, {
    required TextEditingController emailController,
    required FocusNode emailNode,
  }) async {
    final capture = InputFocusCapture(
      sink: sink,
      tracker: tracker,
      nowMs: () => now,
    )..install();
    addTearDown(capture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Semantics(
            label: 'Email',
            child: TextField(controller: emailController, focusNode: emailNode),
          ),
        ),
      ),
    );
    return capture;
  }

  testWidgets('focus emits input_focus with the Semantics identity', (
    tester,
  ) async {
    final controller = TextEditingController();
    final node = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(node.dispose);
    await pumpForm(tester, emailController: controller, emailNode: node);

    node.requestFocus();
    await tester.pump();

    final focus = sink.named('input_focus').single;
    expect(focus.type, EventType.auto);
    expect(focus.props['field'], 'Email');
    expect(focus.props['screen'], 'Form');
    expect(focus.screen, 'Form');
  });

  testWidgets('blur after typing emits input_abandon with dwell + had_input', (
    tester,
  ) async {
    final controller = TextEditingController();
    final node = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(node.dispose);
    await pumpForm(tester, emailController: controller, emailNode: node);

    node.requestFocus();
    await tester.pump();
    controller.text = 'someone@example.com'; // content never leaves device
    now += 750;
    node.unfocus();
    await tester.pump();

    final abandon = sink.named('input_abandon').single;
    expect(abandon.props['field'], 'Email');
    expect(abandon.props['dwell_ms'], 750);
    expect(abandon.props['had_input'], true);
    // Never the content or its length.
    expect(abandon.props.containsKey('value'), isFalse);
    expect(abandon.props.containsKey('length'), isFalse);
  });

  testWidgets('abandon with no text entered reports had_input:false', (
    tester,
  ) async {
    final controller = TextEditingController();
    final node = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(node.dispose);
    await pumpForm(tester, emailController: controller, emailNode: node);

    node.requestFocus();
    await tester.pump();
    node.unfocus();
    await tester.pump();

    expect(sink.named('input_abandon').single.props['had_input'], false);
  });

  testWidgets('a text field without a Semantics label is ignored', (
    tester,
  ) async {
    final capture = InputFocusCapture(sink: sink, tracker: tracker)..install();
    addTearDown(capture.dispose);
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(focusNode: node)),
      ),
    );

    node.requestFocus();
    await tester.pump();
    node.unfocus();
    await tester.pump();

    expect(sink.events, isEmpty);
  });
}
