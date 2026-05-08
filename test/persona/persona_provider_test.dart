import 'package:flutter_test/flutter_test.dart';
import 'package:bubbles/models/persona.dart';
import 'package:bubbles/providers/persona_provider.dart';
import 'package:bubbles/services/persona_service.dart';

class _FakeService implements PersonaService {
  final Persona? toReturn;
  final Object? throwError;
  bool called = false;
  _FakeService({this.toReturn, this.throwError});

  @override
  Future<Persona?> fetchMyPersona() async {
    called = true;
    if (throwError != null) {
      throw throwError!;
    }
    return toReturn;
  }

  @override
  Future<Persona> upsertMyPersona(PersonaUpdate update) async =>
      throw UnimplementedError();

  @override
  Future<void> setSessionContext(
    String sessionId, {
    required String scenario,
    String roleMode = 'default',
    String? notes,
  }) async {}
}

Persona _examplePersona({DateTime? completedAt}) => Persona(
      userId: 'u1',
      rolePrimary: 'teacher',
      nativeLanguage: 'en',
      learningLanguage: 'en',
      roleFamily: 'educator',
      completedAt: completedAt,
      createdAt: DateTime.utc(2026, 5, 9),
      updatedAt: DateTime.utc(2026, 5, 9),
    );

void main() {
  test('PersonaProvider starts in loading state with no persona', () {
    final p = PersonaProvider(service: _FakeService());
    expect(p.loading, true);
    expect(p.persona, null);
    // While loading, needsWizard is false (we don't know yet)
    expect(p.needsWizard, false);
  });

  test('refresh sets persona and clears loading', () async {
    final p = PersonaProvider(
      service: _FakeService(
        toReturn: _examplePersona(completedAt: DateTime.utc(2026, 5, 9)),
      ),
    );
    await p.refresh();
    expect(p.loading, false);
    expect(p.persona, isNotNull);
    expect(p.needsWizard, false);
    expect(p.error, isNull);
  });

  test('refresh with null persona produces needsWizard=true', () async {
    final p = PersonaProvider(service: _FakeService(toReturn: null));
    await p.refresh();
    expect(p.loading, false);
    expect(p.persona, isNull);
    expect(p.needsWizard, true);
  });

  test('refresh with incomplete persona (completed_at null) produces needsWizard=true',
      () async {
    final p = PersonaProvider(
      service: _FakeService(toReturn: _examplePersona(completedAt: null)),
    );
    await p.refresh();
    expect(p.loading, false);
    expect(p.persona, isNotNull);
    expect(p.persona!.isComplete, false);
    expect(p.needsWizard, true);
  });

  test('refresh captures error and clears loading', () async {
    final p = PersonaProvider(
      service: _FakeService(throwError: Exception('boom')),
    );
    await p.refresh();
    expect(p.loading, false);
    expect(p.error, isNotNull);
    expect(p.error, contains('boom'));
  });
}
