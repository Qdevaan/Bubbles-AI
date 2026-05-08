import 'package:flutter_test/flutter_test.dart';
import 'package:bubbles/models/persona.dart';

void main() {
  test('Persona.fromJson parses required fields', () {
    final p = Persona.fromJson({
      'user_id': '00000000-0000-0000-0000-000000000001',
      'role_primary': 'teacher',
      'native_language': 'en',
      'learning_language': 'en',
      'role_family': 'educator',
      'expertise_tags': ['physics'],
      'communication_style': [],
      'primary_goals': [],
      'typical_scenarios': [],
      'formality_preference': 'neutral',
      'completed_at': '2026-05-09T00:00:00Z',
      'created_at': '2026-05-09T00:00:00Z',
      'updated_at': '2026-05-09T00:00:00Z',
    });
    expect(p.rolePrimary, 'teacher');
    expect(p.roleFamily, 'educator');
    expect(p.expertiseTags, ['physics']);
    expect(p.isComplete, true);
  });

  test('Persona.fromJson handles missing optional fields gracefully', () {
    final p = Persona.fromJson({
      'user_id': 'u1',
      'role_primary': 'student',
      'native_language': 'ur',
      'role_family': 'learner',
      'created_at': '2026-05-09T00:00:00Z',
      'updated_at': '2026-05-09T00:00:00Z',
    });
    expect(p.learningLanguage, 'en'); // default fallback
    expect(p.formalityPreference, 'neutral');
    expect(p.expertiseTags, isEmpty);
    expect(p.communicationStyle, isEmpty);
    expect(p.completedAt, isNull);
    expect(p.isComplete, false);
  });

  test('PersonaUpdate.toJson omits null fields', () {
    final j = const PersonaUpdate(rolePrimary: 'student', nativeLanguage: 'en')
        .toJson();
    expect(j.containsKey('role_primary'), true);
    expect(j['role_primary'], 'student');
    expect(j.containsKey('native_language'), true);
    expect(j.containsKey('display_name'), false);
    expect(j.containsKey('age_range'), false);
    expect(j.containsKey('expertise_tags'), false);
  });

  test('PersonaUpdate.toJson includes list fields when provided', () {
    final j = const PersonaUpdate(
      expertiseTags: ['physics', 'math'],
      primaryGoals: ['fluency'],
    ).toJson();
    expect(j['expertise_tags'], ['physics', 'math']);
    expect(j['primary_goals'], ['fluency']);
    expect(j.containsKey('typical_scenarios'), false);
  });
}
