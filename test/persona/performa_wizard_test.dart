// Widget tests for PerformaWizardScreen. We use a stub ApiService and a
// PersonaService backed by it so we don't have to bring up Supabase. The
// wizard never actually calls the service in these tests (we don't tap
// Finish), so the stub's behavior is unused beyond construction.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bubbles/models/persona.dart';
import 'package:bubbles/providers/persona_provider.dart';
import 'package:bubbles/screens/performa/performa_wizard_screen.dart';
import 'package:bubbles/services/api_service.dart';
import 'package:bubbles/services/persona_service.dart';

class _StubApiService implements ApiService {
  @override
  Future<Map<String, dynamic>?> getMyPersona() async => null;

  @override
  Future<Map<String, dynamic>> upsertMyPersona(PersonaUpdate update) async =>
      <String, dynamic>{};

  @override
  Future<void> setSessionContext(
    String sessionId, {
    required String scenario,
    String roleMode = 'default',
    String? notes,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PersonaProvider _buildProvider() => PersonaProvider(
      service: PersonaService(_StubApiService()),
    );

void main() {
  testWidgets('wizard shows step 1 first and Next disabled until role selected',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => _buildProvider(),
          child: const PerformaWizardScreen(),
        ),
      ),
    );

    expect(find.text('About you'), findsOneWidget);
    final nextBtn = find.widgetWithText(ElevatedButton, 'Next');
    expect(nextBtn, findsOneWidget);
    expect(tester.widget<ElevatedButton>(nextBtn).onPressed, isNull);
  });

  testWidgets('selecting role enables Next on step 1', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => _buildProvider(),
          child: const PerformaWizardScreen(),
        ),
      ),
    );

    await tester.tap(find.text('Teacher'));
    await tester.pumpAndSettle();

    final nextBtn = find.widgetWithText(ElevatedButton, 'Next');
    expect(tester.widget<ElevatedButton>(nextBtn).onPressed, isNotNull);
  });
}
