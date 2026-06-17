// Purpose: Draft/scratch file for the Performa persona wizard — not yet active in production routing.
import 'package:bubbles/models/persona.dart';

/// Mutable draft used to back the multi-step PerformaWizard. Step widgets
/// mutate this object directly and call their `onChanged` callback so the
/// wizard re-evaluates Next-button enable state. When the user finishes the
/// wizard, [toUpdate] produces a [PersonaUpdate] sent to the API.
class PerformaDraft {
  String? displayName;
  String? ageRange;
  String? rolePrimary;
  String? professionDetail;
  List<String> expertiseTags = [];
  String? nativeLanguage;
  String? learningLanguage = 'en';
  String? proficiencySelfRated;
  String formalityPreference = 'neutral';
  List<String> communicationStyle = [];
  List<String> primaryGoals = [];
  List<String> typicalScenarios = [];
  String? culturalContext;
  String? avoidList;

  PersonaUpdate toUpdate() => PersonaUpdate(
        displayName: displayName,
        ageRange: ageRange,
        rolePrimary: rolePrimary,
        professionDetail: professionDetail,
        expertiseTags: expertiseTags.isEmpty ? null : expertiseTags,
        nativeLanguage: nativeLanguage,
        learningLanguage: learningLanguage,
        proficiencySelfRated: proficiencySelfRated,
        formalityPreference: formalityPreference,
        communicationStyle:
            communicationStyle.isEmpty ? null : communicationStyle,
        primaryGoals: primaryGoals.isEmpty ? null : primaryGoals,
        typicalScenarios: typicalScenarios.isEmpty ? null : typicalScenarios,
        culturalContext: culturalContext,
        avoidList: avoidList,
      );
}
