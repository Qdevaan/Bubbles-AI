// Purpose: Data models for AI-generated scenarios: Scenario and StartScenarioResponse.
enum ScenarioStatus { suggested, started, completed, dismissed, unknown }

ScenarioStatus parseScenarioStatus(String? s) {
  switch (s) {
    case 'suggested':
      return ScenarioStatus.suggested;
    case 'started':
      return ScenarioStatus.started;
    case 'completed':
      return ScenarioStatus.completed;
    case 'dismissed':
      return ScenarioStatus.dismissed;
    default:
      return ScenarioStatus.unknown;
  }
}

enum ScenarioDifficulty { easy, medium, hard, unknown }

ScenarioDifficulty parseDifficulty(String? s) {
  switch (s?.toLowerCase()) {
    case 'easy':
      return ScenarioDifficulty.easy;
    case 'medium':
      return ScenarioDifficulty.medium;
    case 'hard':
      return ScenarioDifficulty.hard;
    default:
      return ScenarioDifficulty.unknown;
  }
}

class Scenario {
  final String id;
  final String title;
  final String situation;
  final String goal;
  final List<String> successCriteria;
  final ScenarioDifficulty difficulty;
  final String roleMode;
  final String openingLine;
  final String? targetEntityId;
  final String? targetEntityName;
  final ScenarioStatus status;
  final String? sessionId;
  final bool? passed;
  final String? scoreFeedback;
  final DateTime? createdAt;
  final Map<String, dynamic> source;

  const Scenario({
    required this.id,
    required this.title,
    required this.situation,
    required this.goal,
    required this.successCriteria,
    required this.difficulty,
    required this.roleMode,
    required this.openingLine,
    required this.targetEntityId,
    required this.targetEntityName,
    required this.status,
    required this.sessionId,
    required this.passed,
    required this.scoreFeedback,
    required this.createdAt,
    required this.source,
  });

  factory Scenario.fromJson(Map<String, dynamic> j) {
    List<String> sc;
    final raw = j['success_criteria'];
    if (raw is List) {
      sc = [for (final r in raw) r.toString()];
    } else if (raw is String && raw.isNotEmpty) {
      sc = raw
          .split(RegExp(r'[\n;,]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      sc = const [];
    }
    final src = j['source'];
    return Scenario(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      situation: (j['situation'] ?? '').toString(),
      goal: (j['goal'] ?? '').toString(),
      successCriteria: sc,
      difficulty: parseDifficulty(j['difficulty']?.toString()),
      roleMode: (j['role_mode'] ?? 'default').toString(),
      openingLine: (j['opening_line'] ?? '').toString(),
      targetEntityId: j['target_entity_id']?.toString(),
      targetEntityName: j['target_entity_name']?.toString(),
      status: parseScenarioStatus(j['status']?.toString()),
      sessionId: j['session_id']?.toString(),
      passed: j['passed'] as bool?,
      scoreFeedback: j['score_feedback']?.toString(),
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
      source: src is Map<String, dynamic> ? src : const {},
    );
  }
}

class StartScenarioResponse {
  final String sessionId;
  final Scenario scenario;

  const StartScenarioResponse({
    required this.sessionId,
    required this.scenario,
  });

  factory StartScenarioResponse.fromJson(Map<String, dynamic> j) =>
      StartScenarioResponse(
        sessionId: (j['session_id'] ?? '').toString(),
        scenario: Scenario.fromJson(
          (j['scenario'] as Map?)?.cast<String, dynamic>() ??
              const {},
        ),
      );
}
