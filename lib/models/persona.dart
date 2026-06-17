// Purpose: Persona model — represents the full Performa user persona with goals, style, and language attributes.
class Persona {
  final String userId;
  final String? displayName;
  final String? ageRange;
  final String rolePrimary;
  final String? professionDetail;
  final List<String> expertiseTags;
  final String nativeLanguage;
  final String learningLanguage;
  final String? proficiencySelfRated;
  final String formalityPreference;
  final List<String> communicationStyle;
  final List<String> primaryGoals;
  final List<String> typicalScenarios;
  final String? culturalContext;
  final String? avoidList;
  final String roleFamily;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Persona({
    required this.userId,
    this.displayName,
    this.ageRange,
    required this.rolePrimary,
    this.professionDetail,
    this.expertiseTags = const [],
    required this.nativeLanguage,
    required this.learningLanguage,
    this.proficiencySelfRated,
    this.formalityPreference = 'neutral',
    this.communicationStyle = const [],
    this.primaryGoals = const [],
    this.typicalScenarios = const [],
    this.culturalContext,
    this.avoidList,
    required this.roleFamily,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isComplete => completedAt != null;

  factory Persona.fromJson(Map<String, dynamic> j) => Persona(
        userId: j['user_id'] as String,
        displayName: j['display_name'] as String?,
        ageRange: j['age_range'] as String?,
        rolePrimary: j['role_primary'] as String,
        professionDetail: j['profession_detail'] as String?,
        expertiseTags: List<String>.from(j['expertise_tags'] ?? const []),
        nativeLanguage: j['native_language'] as String,
        learningLanguage: j['learning_language'] as String? ?? 'en',
        proficiencySelfRated: j['proficiency_self_rated'] as String?,
        formalityPreference:
            j['formality_preference'] as String? ?? 'neutral',
        communicationStyle:
            List<String>.from(j['communication_style'] ?? const []),
        primaryGoals: List<String>.from(j['primary_goals'] ?? const []),
        typicalScenarios:
            List<String>.from(j['typical_scenarios'] ?? const []),
        culturalContext: j['cultural_context'] as String?,
        avoidList: j['avoid_list'] as String?,
        roleFamily: j['role_family'] as String,
        completedAt: j['completed_at'] != null
            ? DateTime.parse(j['completed_at'] as String)
            : null,
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
      );
}

class PersonaUpdate {
  final String? displayName;
  final String? ageRange;
  final String? rolePrimary;
  final String? professionDetail;
  final List<String>? expertiseTags;
  final String? nativeLanguage;
  final String? learningLanguage;
  final String? proficiencySelfRated;
  final String? formalityPreference;
  final List<String>? communicationStyle;
  final List<String>? primaryGoals;
  final List<String>? typicalScenarios;
  final String? culturalContext;
  final String? avoidList;

  const PersonaUpdate({
    this.displayName,
    this.ageRange,
    this.rolePrimary,
    this.professionDetail,
    this.expertiseTags,
    this.nativeLanguage,
    this.learningLanguage,
    this.proficiencySelfRated,
    this.formalityPreference,
    this.communicationStyle,
    this.primaryGoals,
    this.typicalScenarios,
    this.culturalContext,
    this.avoidList,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (displayName != null) m['display_name'] = displayName;
    if (ageRange != null) m['age_range'] = ageRange;
    if (rolePrimary != null) m['role_primary'] = rolePrimary;
    if (professionDetail != null) m['profession_detail'] = professionDetail;
    if (expertiseTags != null) m['expertise_tags'] = expertiseTags;
    if (nativeLanguage != null) m['native_language'] = nativeLanguage;
    if (learningLanguage != null) m['learning_language'] = learningLanguage;
    if (proficiencySelfRated != null) {
      m['proficiency_self_rated'] = proficiencySelfRated;
    }
    if (formalityPreference != null) {
      m['formality_preference'] = formalityPreference;
    }
    if (communicationStyle != null) {
      m['communication_style'] = communicationStyle;
    }
    if (primaryGoals != null) m['primary_goals'] = primaryGoals;
    if (typicalScenarios != null) m['typical_scenarios'] = typicalScenarios;
    if (culturalContext != null) m['cultural_context'] = culturalContext;
    if (avoidList != null) m['avoid_list'] = avoidList;
    return m;
  }
}
