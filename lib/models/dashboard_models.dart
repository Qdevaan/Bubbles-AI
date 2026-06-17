// Purpose: Dashboard data models — typed wrappers for the dashboard payload returned by the stats endpoint.
/// Models for the F3 longitudinal progress dashboard payload.
///
/// Shape mirrors `/v1/dashboard?range=...` exactly:
/// `{range, granularity, window:{start,end}, summary:{...}, series:{...}}`.

class DashboardBucket {
  final DateTime bucket;
  final num? value; // null = gap (sentiment only)

  const DashboardBucket({required this.bucket, required this.value});

  factory DashboardBucket.fromJson(Map<String, dynamic> j) {
    final raw = j['bucket'];
    DateTime parsed;
    if (raw is DateTime) {
      parsed = raw;
    } else {
      parsed = DateTime.tryParse(raw.toString()) ?? DateTime.now();
    }
    return DashboardBucket(
      bucket: parsed,
      value: j['value'] is num ? j['value'] as num : null,
    );
  }
}

class MetricDelta {
  final num current;
  final num? previous;
  final double? deltaPct;

  const MetricDelta({
    required this.current,
    required this.previous,
    required this.deltaPct,
  });

  factory MetricDelta.fromJson(Map<String, dynamic> j) => MetricDelta(
        current: (j['current'] as num?) ?? 0,
        previous: j['previous'] as num?,
        deltaPct: (j['delta_pct'] as num?)?.toDouble(),
      );
}

class DashboardSummary {
  final MetricDelta totalXp;
  final MetricDelta sessions;
  final MetricDelta mistakes;
  final MetricDelta avgSentiment;
  final MetricDelta talkTimeMinutes;
  final int? drillMasteryPct;
  final int currentStreak;
  final int level;
  final int dueDrillCount;

  const DashboardSummary({
    required this.totalXp,
    required this.sessions,
    required this.mistakes,
    required this.avgSentiment,
    required this.talkTimeMinutes,
    required this.drillMasteryPct,
    required this.currentStreak,
    required this.level,
    required this.dueDrillCount,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> j) {
    MetricDelta m(String k) => MetricDelta.fromJson(
        (j[k] as Map?)?.cast<String, dynamic>() ?? const {});
    return DashboardSummary(
      totalXp: m('total_xp'),
      sessions: m('sessions'),
      mistakes: m('mistakes'),
      avgSentiment: m('avg_sentiment'),
      talkTimeMinutes: m('talk_time_minutes'),
      drillMasteryPct: (j['drill_mastery_pct'] as num?)?.toInt(),
      currentStreak: (j['current_streak'] as num?)?.toInt() ?? 0,
      level: (j['level'] as num?)?.toInt() ?? 1,
      dueDrillCount: (j['due_drill_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class DashboardSeries {
  final List<DashboardBucket> xp;
  final List<DashboardBucket> sessions;
  final List<DashboardBucket> mistakes;
  final List<DashboardBucket> sentiment;
  final List<DashboardBucket> talkTime;

  const DashboardSeries({
    required this.xp,
    required this.sessions,
    required this.mistakes,
    required this.sentiment,
    required this.talkTime,
  });

  factory DashboardSeries.fromJson(Map<String, dynamic> j) {
    List<DashboardBucket> series(String k) {
      final raw = j[k];
      if (raw is! List) return const [];
      return [
        for (final b in raw)
          if (b is Map<String, dynamic>) DashboardBucket.fromJson(b),
      ];
    }

    return DashboardSeries(
      xp: series('xp_per_bucket'),
      sessions: series('sessions_per_bucket'),
      mistakes: series('mistakes_per_bucket'),
      sentiment: series('avg_sentiment_per_bucket'),
      talkTime: series('talk_time_minutes_per_bucket'),
    );
  }
}

class DashboardResponse {
  final String range; // 30d | 90d | 365d
  final String granularity; // daily | weekly | monthly
  final DateTime windowStart;
  final DateTime windowEnd;
  final DashboardSummary summary;
  final DashboardSeries series;

  const DashboardResponse({
    required this.range,
    required this.granularity,
    required this.windowStart,
    required this.windowEnd,
    required this.summary,
    required this.series,
  });

  factory DashboardResponse.fromJson(Map<String, dynamic> j) {
    final w = (j['window'] as Map?)?.cast<String, dynamic>() ?? const {};
    return DashboardResponse(
      range: (j['range'] ?? '30d').toString(),
      granularity: (j['granularity'] ?? 'daily').toString(),
      windowStart: DateTime.tryParse(w['start']?.toString() ?? '') ??
          DateTime.now().subtract(const Duration(days: 30)),
      windowEnd: DateTime.tryParse(w['end']?.toString() ?? '') ??
          DateTime.now(),
      summary: DashboardSummary.fromJson(
        (j['summary'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      series: DashboardSeries.fromJson(
        (j['series'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }
}
