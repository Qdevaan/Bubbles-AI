// Purpose: Data models for spaced-repetition drills: DrillCard, DrillResult, and ReviewResponse.
import 'dart:convert';

class DrillExample {
  final String mistakeId;
  final String snippet;
  final String? suggestion;
  final DateTime? createdAt;

  const DrillExample({
    required this.mistakeId,
    required this.snippet,
    this.suggestion,
    this.createdAt,
  });

  factory DrillExample.fromJson(Map<String, dynamic> j) => DrillExample(
        mistakeId: (j['mistake_id'] ?? '').toString(),
        snippet: (j['snippet'] ?? '').toString(),
        suggestion: j['suggestion']?.toString(),
        createdAt: _parseDate(j['created_at']),
      );
}

class DrillCard {
  final String id;
  final String userId;
  final String ruleId;
  final String category;
  final int box;
  final DateTime? dueAt;
  final DateTime? lastReviewedAt;
  final int correctStreak;
  final int totalReviews;
  final int totalCorrect;
  final DateTime? retiredAt;
  final List<DrillExample> examples;
  final int examplesCount;

  const DrillCard({
    required this.id,
    required this.userId,
    required this.ruleId,
    required this.category,
    required this.box,
    required this.dueAt,
    required this.lastReviewedAt,
    required this.correctStreak,
    required this.totalReviews,
    required this.totalCorrect,
    required this.retiredAt,
    required this.examples,
    required this.examplesCount,
  });

  bool get isRetired => retiredAt != null;
  bool get isMastered => box >= 5;

  /// Most recent snippet (server stores newest at index 0).
  String? get frontSnippet =>
      examples.isNotEmpty ? examples.first.snippet : null;

  /// Most recent suggested correction.
  String? get backSuggestion =>
      examples.isNotEmpty ? examples.first.suggestion : null;

  factory DrillCard.fromJson(Map<String, dynamic> j) {
    final rawExamples = j['examples'];
    final examples = <DrillExample>[];
    if (rawExamples is List) {
      for (final e in rawExamples) {
        if (e is Map<String, dynamic>) examples.add(DrillExample.fromJson(e));
      }
    } else if (rawExamples is String && rawExamples.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawExamples);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map<String, dynamic>) {
              examples.add(DrillExample.fromJson(e));
            }
          }
        }
      } catch (_) {}
    }
    final declaredCount = (j['examples_count'] as num?)?.toInt();
    return DrillCard(
      id: (j['id'] ?? '').toString(),
      userId: (j['user_id'] ?? '').toString(),
      ruleId: (j['rule_id'] ?? '').toString(),
      category: (j['category'] ?? '').toString(),
      box: (j['box'] as num?)?.toInt() ?? 1,
      dueAt: _parseDate(j['due_at']),
      lastReviewedAt: _parseDate(j['last_reviewed_at']),
      correctStreak: (j['correct_streak'] as num?)?.toInt() ?? 0,
      totalReviews: (j['total_reviews'] as num?)?.toInt() ?? 0,
      totalCorrect: (j['total_correct'] as num?)?.toInt() ?? 0,
      retiredAt: _parseDate(j['retired_at']),
      examples: examples,
      examplesCount: declaredCount ?? examples.length,
    );
  }
}

class DrillQueueResponse {
  final List<DrillCard> cards;
  final int totalDue;
  final bool isUpcoming;

  const DrillQueueResponse({
    required this.cards,
    required this.totalDue,
    required this.isUpcoming,
  });

  factory DrillQueueResponse.fromJson(Map<String, dynamic> j) {
    final list = (j['cards'] as List?) ?? const [];
    return DrillQueueResponse(
      cards: [
        for (final c in list)
          if (c is Map<String, dynamic>) DrillCard.fromJson(c),
      ],
      totalDue: (j['total_due'] as num?)?.toInt() ?? 0,
      isUpcoming: j['is_upcoming'] == true,
    );
  }
}

enum DrillResult { correct, wrong }

class ReviewDrillResponse {
  final DrillCard card;
  final int xpAwarded;
  final String transition; // e.g. "1->2"

  const ReviewDrillResponse({
    required this.card,
    required this.xpAwarded,
    required this.transition,
  });

  factory ReviewDrillResponse.fromJson(Map<String, dynamic> j) =>
      ReviewDrillResponse(
        card: DrillCard.fromJson((j['card'] as Map).cast<String, dynamic>()),
        xpAwarded: (j['xp_awarded'] as num?)?.toInt() ?? 0,
        transition: (j['transition'] ?? '').toString(),
      );
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString())?.toUtc();
}
