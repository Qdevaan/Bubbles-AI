class PerformaContact {
  final String name;
  final String relationship;
  final String notes;
  final DateTime? lastSeenAt;

  const PerformaContact({
    required this.name,
    required this.relationship,
    this.notes = '',
    this.lastSeenAt,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'relationship': relationship,
    'notes': notes,
    if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.toIso8601String(),
  };

  factory PerformaContact.fromJson(Map<String, dynamic> j) => PerformaContact(
    name: j['name'] as String? ?? '',
    relationship: j['relationship'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    lastSeenAt: j['lastSeenAt'] != null ? DateTime.tryParse(j['lastSeenAt'] as String) : null,
  );

  PerformaContact copyWith({String? name, String? relationship, String? notes}) =>
      PerformaContact(
        name: name ?? this.name,
        relationship: relationship ?? this.relationship,
        notes: notes ?? this.notes,
        lastSeenAt: lastSeenAt,
      );
}

class PerformaInsight {
  final String id;
  final String text;
  final String source; // session_id
  final double confidence;
  final DateTime addedAt;
  final bool approved;

  const PerformaInsight({
    required this.id,
    required this.text,
    required this.source,
    required this.confidence,
    required this.addedAt,
    required this.approved,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'source': source,
    'confidence': confidence,
    'addedAt': addedAt.toIso8601String(),
    'approved': approved,
  };

  factory PerformaInsight.fromJson(Map<String, dynamic> j) => PerformaInsight(
    id: j['id'] as String? ?? '',
    text: j['text'] as String? ?? '',
    source: j['source'] as String? ?? '',
    confidence: (j['confidence'] as num?)?.toDouble() ?? 0.7,
    addedAt: j['addedAt'] != null
        ? (DateTime.tryParse(j['addedAt'] as String) ?? DateTime.now())
        : DateTime.now(),
    approved: j['approved'] as bool? ?? false,
  );

  PerformaInsight copyWith({String? text, bool? approved}) => PerformaInsight(
    id: id,
    text: text ?? this.text,
    source: source,
    confidence: confidence,
    addedAt: addedAt,
    approved: approved ?? this.approved,
  );
}

class Performa {
  final String userId;

  final String fullName;
  final String role;
  final String industry;
  final String company;
  final List<String> goals;
  final List<String> conversationScenarios;
  final List<String> languages;
  final String communicationStyle;
  final List<PerformaContact> recurringContacts;
  final List<String> customKeywords;
  final String background;

  final List<PerformaInsight> aiInsights;
  final List<String> inferredStrengths;
  final List<String> inferredWeaknesses;
  final List<String> notablePatterns;

  const Performa({
    required this.userId,
    this.fullName = '',
    this.role = '',
    this.industry = '',
    this.company = '',
    this.goals = const [],
    this.conversationScenarios = const [],
    this.languages = const [],
    this.communicationStyle = '',
    this.recurringContacts = const [],
    this.customKeywords = const [],
    this.background = '',
    this.aiInsights = const [],
    this.inferredStrengths = const [],
    this.inferredWeaknesses = const [],
    this.notablePatterns = const [],
  });

  List<PerformaInsight> get pendingInsights =>
      aiInsights.where((i) => !i.approved).toList();

  Map<String, dynamic> toManualJson() => {
    'fullName': fullName,
    'role': role,
    'industry': industry,
    'company': company,
    'goals': goals,
    'conversationScenarios': conversationScenarios,
    'languages': languages,
    'communicationStyle': communicationStyle,
    'recurringContacts': recurringContacts.map((c) => c.toJson()).toList(),
    'customKeywords': customKeywords,
    'background': background,
  };

  factory Performa.fromSupabaseRow(Map<String, dynamic> row) {
    final m = (row['manual_data'] as Map<String, dynamic>?) ?? {};
    final a = (row['ai_data'] as Map<String, dynamic>?) ?? {};

    List<T> listOf<T>(dynamic raw, T Function(dynamic) parse) =>
        (raw as List?)?.map(parse).toList() ?? [];

    return Performa(
      userId: row['user_id'] as String? ?? '',
      fullName: m['fullName'] as String? ?? '',
      role: m['role'] as String? ?? '',
      industry: m['industry'] as String? ?? '',
      company: m['company'] as String? ?? '',
      goals: listOf(m['goals'], (e) => e as String),
      conversationScenarios: listOf(m['conversationScenarios'], (e) => e as String),
      languages: listOf(m['languages'], (e) => e as String),
      communicationStyle: m['communicationStyle'] as String? ?? '',
      recurringContacts: listOf(m['recurringContacts'], (e) => PerformaContact.fromJson(e as Map<String, dynamic>)),
      customKeywords: listOf(m['customKeywords'], (e) => e as String),
      background: m['background'] as String? ?? '',
      aiInsights: listOf(a['aiInsights'], (e) => PerformaInsight.fromJson(e as Map<String, dynamic>)),
      inferredStrengths: listOf(a['inferredStrengths'], (e) => e as String),
      inferredWeaknesses: listOf(a['inferredWeaknesses'], (e) => e as String),
      notablePatterns: listOf(a['notablePatterns'], (e) => e as String),
    );
  }

  Performa copyWith({
    String? fullName, String? role, String? industry, String? company,
    List<String>? goals, List<String>? conversationScenarios,
    List<String>? languages, String? communicationStyle,
    List<PerformaContact>? recurringContacts, List<String>? customKeywords,
    String? background, List<PerformaInsight>? aiInsights,
  }) => Performa(
    userId: userId,
    fullName: fullName ?? this.fullName,
    role: role ?? this.role,
    industry: industry ?? this.industry,
    company: company ?? this.company,
    goals: goals ?? this.goals,
    conversationScenarios: conversationScenarios ?? this.conversationScenarios,
    languages: languages ?? this.languages,
    communicationStyle: communicationStyle ?? this.communicationStyle,
    recurringContacts: recurringContacts ?? this.recurringContacts,
    customKeywords: customKeywords ?? this.customKeywords,
    background: background ?? this.background,
    aiInsights: aiInsights ?? this.aiInsights,
    inferredStrengths: inferredStrengths,
    inferredWeaknesses: inferredWeaknesses,
    notablePatterns: notablePatterns,
  );
}
