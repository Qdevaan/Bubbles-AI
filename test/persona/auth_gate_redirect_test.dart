import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bubbles/models/persona.dart';
import 'package:bubbles/providers/persona_provider.dart';
import 'package:bubbles/screens/auth_gate.dart';
import 'package:bubbles/services/api_service.dart';
import 'package:bubbles/services/persona_service.dart';

class _StubApi implements ApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _NoPersonaService extends PersonaService {
  _NoPersonaService() : super(_StubApi());

  @override
  Future<Persona?> fetchMyPersona() async => null;
}

class _CompletePersonaService extends PersonaService {
  _CompletePersonaService() : super(_StubApi());

  @override
  Future<Persona?> fetchMyPersona() async => Persona(
        userId: 'u1',
        rolePrimary: 'teacher',
        nativeLanguage: 'en',
        learningLanguage: 'en',
        roleFamily: 'educator',
        completedAt: DateTime.utc(2026, 5, 9),
        createdAt: DateTime.utc(2026, 5, 9),
        updatedAt: DateTime.utc(2026, 5, 9),
      );
}

void main() {
  testWidgets('auth gate routes to wizard when persona incomplete',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => PersonaProvider(service: _NoPersonaService()),
          child: const AuthGate(),
        ),
        routes: {
          '/performa-wizard': (_) =>
              const Scaffold(body: Text('WIZARD')),
          '/home': (_) => const Scaffold(body: Text('HOME')),
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('WIZARD'), findsOneWidget);
  });

  testWidgets('auth gate routes to home when persona complete',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => PersonaProvider(service: _CompletePersonaService()),
          child: const AuthGate(),
        ),
        routes: {
          '/performa-wizard': (_) =>
              const Scaffold(body: Text('WIZARD')),
          '/home': (_) => const Scaffold(body: Text('HOME')),
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });
}
