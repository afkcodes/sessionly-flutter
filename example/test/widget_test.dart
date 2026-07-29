// A minimal smoke test: the instrumented app builds, shows the home screen, and
// navigation works — without requiring the SDK to be initialized (the ambient
// runtime is null, so every capture surface is an inert no-op).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sessionly_example/main.dart';

void main() {
  testWidgets('home renders and navigates to the list screen', (tester) async {
    await tester.pumpWidget(const SessionlyExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.byKey(const ValueKey('rage_target')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('go_list')));
    await tester.pumpAndSettle();
    expect(find.text('List'), findsOneWidget);
  });
}
