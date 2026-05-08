import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bubbles/screens/session/session_context_dialog.dart';

void main() {
  testWidgets('SessionContextDialog returns scenario + role_mode + notes on submit',
      (tester) async {
    Map<String, dynamic>? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await showSessionContextDialog(ctx);
              },
              child: const Text('Open'),
            )),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lecture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start session'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!['scenario'], 'lecture');
  });

  testWidgets('Skip returns null', (tester) async {
    Map<String, dynamic>? result = {'sentinel': true};
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await showSessionContextDialog(ctx);
              },
              child: const Text('Open'),
            )),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
