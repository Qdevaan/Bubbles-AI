// PersonaService is a thin wrapper around ApiService — the JSON parsing it
// depends on is exhaustively covered by `persona_model_test.dart`, and the
// HTTP layer is covered by integration tests for ApiService. This file
// verifies the wrapper's parsing behavior using a stub ApiService.

import 'package:flutter_test/flutter_test.dart';
import 'package:bubbles/models/persona.dart';
import 'package:bubbles/services/api_service.dart';
import 'package:bubbles/services/persona_service.dart';

class _StubApiService implements ApiService {
  Map<String, dynamic>? personaToReturn;
  Map<String, dynamic>? upsertReturn;
  bool setContextCalled = false;
  String? lastSessionId;
  String? lastScenario;

  @override
  Future<Map<String, dynamic>?> getMyPersona() async => personaToReturn;

  @override
  Future<Map<String, dynamic>> upsertMyPersona(PersonaUpdate update) async =>
      upsertReturn ?? <String, dynamic>{};

  @override
  Future<void> setSessionContext(
    String sessionId, {
    required String scenario,
    String roleMode = 'default',
    String? notes,
  }) async {
    setContextCalled = true;
    lastSessionId = sessionId;
    lastScenario = scenario;
  }

  // Catch-all for the rest of ApiService surface area we don't exercise.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _examplePersonaJson({String? completedAt}) => {
      'user_id': 'u1',
      'role_primary': 'teacher',
      'native_language': 'en',
      'learning_language': 'en',
      'role_family': 'educator',
      'created_at': '2026-05-09T00:00:00Z',
      'updated_at': '2026-05-09T00:00:00Z',
      if (completedAt != null) 'completed_at': completedAt,
    };

void main() {
  test('fetchMyPersona returns null when api returns null (404)', () async {
    final api = _StubApiService()..personaToReturn = null;
    final svc = PersonaService(api);
    expect(await svc.fetchMyPersona(), isNull);
  });

  test('fetchMyPersona parses a Persona from raw JSON', () async {
    final api = _StubApiService()
      ..personaToReturn = _examplePersonaJson(completedAt: '2026-05-09T00:00:00Z');
    final svc = PersonaService(api);
    final p = await svc.fetchMyPersona();
    expect(p, isNotNull);
    expect(p!.rolePrimary, 'teacher');
    expect(p.isComplete, true);
  });

  test('upsertMyPersona returns parsed Persona', () async {
    final api = _StubApiService()
      ..upsertReturn = _examplePersonaJson(completedAt: '2026-05-09T00:00:00Z');
    final svc = PersonaService(api);
    final p = await svc.upsertMyPersona(const PersonaUpdate(rolePrimary: 'teacher'));
    expect(p.rolePrimary, 'teacher');
  });

  test('setSessionContext delegates to api', () async {
    final api = _StubApiService();
    final svc = PersonaService(api);
    await svc.setSessionContext('s1', scenario: 'job_interview');
    expect(api.setContextCalled, true);
    expect(api.lastSessionId, 's1');
    expect(api.lastScenario, 'job_interview');
  });
}
