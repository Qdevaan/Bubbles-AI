import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

/// Displays post-session analytics (session_analytics) and coaching report
/// (coaching_reports) for a given Live Wingman session. (schema_v2 B5 / G2)
class SessionAnalyticsScreen extends StatefulWidget {
  final String sessionId;
  final String sessionTitle;

  const SessionAnalyticsScreen({
    super.key,
    required this.sessionId,
    required this.sessionTitle,
  });

  @override
  State<SessionAnalyticsScreen> createState() => _SessionAnalyticsScreenState();
}

class _SessionAnalyticsScreenState extends State<SessionAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _analytics;
  Map<String, dynamic>? _report;
  bool _analyticsLoading = true;
  bool _reportLoading = true;
  String? _analyticsError;
  String? _reportError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();
  }

  Future<void> _fetchData() async {
    final api = context.read<ApiService>();
    // Fetch analytics
    try {
      final a = await api.getSessionAnalytics(widget.sessionId);
      if (mounted) setState(() { _analytics = a; _analyticsLoading = false; _analyticsError = a == null ? 'Not yet computed' : null; });
    } catch (e) {
      if (mounted) setState(() { _analyticsLoading = false; _analyticsError = 'Failed to load'; });
    }
    // Fetch coaching report (can be slow — generates on demand)
    try {
      final r = await api.getCoachingReport(widget.sessionId);
      if (mounted) setState(() { _report = r; _reportLoading = false; _reportError = r == null ? 'Not available' : null; });
    } catch (e) {
      if (mounted) setState(() { _reportLoading = false; _reportError = 'Failed to load'; });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session Report', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text(widget.sessionTitle, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withOpacity(0.6)), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.analytics_outlined), text: 'Analytics'),
            Tab(icon: Icon(Icons.school_outlined), text: 'Coaching'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _AnalyticsTab(analytics: _analytics, loading: _analyticsLoading, error: _analyticsError),
          _CoachingTab(report: _report, loading: _reportLoading, error: _reportError),
        ],
      ),
    );
  }
}

// ── Analytics Tab ─────────────────────────────────────────────────────────────
class _AnalyticsTab extends StatelessWidget {
  final Map<String, dynamic>? analytics;
  final bool loading;
  final String? error;
  const _AnalyticsTab({required this.analytics, required this.loading, required this.error});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Computing analytics…')]));
    if (error != null || analytics == null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.bar_chart_outlined, size: 48), SizedBox(height: 12), Text(error ?? 'No data yet')]));
    final a = analytics!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(title: '⚡ At a Glance', children: [
          _StatRow('Total Turns', '${a['total_turns'] ?? 0}'),
          _StatRow('Your Turns', '${a['user_turns'] ?? 0}'),
          _StatRow('Others\' Turns', '${a['others_turns'] ?? 0}'),
          _StatRow('AI Advice Count', '${a['llm_turns'] ?? 0}'),
          if (a['total_duration_seconds'] != null)
            _StatRow('Duration', _formatDuration((a['total_duration_seconds'] as num).toDouble())),
          if (a['avg_advice_latency_ms'] != null)
            _StatRow('Avg Latency', '${(a['avg_advice_latency_ms'] as num).toStringAsFixed(0)} ms'),
        ]),
        const SizedBox(height: 12),
        _SectionCard(title: '🗣️ Talk-Time & Engagement', children: [
          if (a['talk_time_user_seconds'] != null)
            _StatRow('Your Talk Time', _formatDuration((a['talk_time_user_seconds'] as num).toDouble())),
          if (a['talk_time_others_seconds'] != null)
            _StatRow('Others\' Talk Time', _formatDuration((a['talk_time_others_seconds'] as num).toDouble())),
          if (a['longest_monologue_seconds'] != null)
            _StatRow('Longest Monologue', _formatDuration((a['longest_monologue_seconds'] as num).toDouble())),
          if (a['user_filler_count'] != null)
            _StatRow('Filler Words Used', '${a['user_filler_count']}'),
          if (a['mutual_engagement_score'] != null)
            _StatRow('Engagement Score', '${(a['mutual_engagement_score'] as num).toStringAsFixed(1)} / 10.0'),
        ]),
        const SizedBox(height: 12),
        _SectionCard(title: '😊 Sentiment', children: [
          _StatRow('Dominant Mood', _capitalize('${a['dominant_sentiment'] ?? 'unknown'}')),
          if (a['avg_sentiment_score'] != null)
            _StatRow('Avg Score', (a['avg_sentiment_score'] as num).toStringAsFixed(3)),
          if (a['sentiment_trend'] != null &&
              (a['sentiment_trend'] as List).isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Emotion Flow:', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              width: double.infinity,
              child: _SentimentLineChart(
                trend: a['sentiment_trend'] as List,
              ),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        _SectionCard(title: '🧠 Memory & Insights', children: [
          _StatRow('Memories Saved', '${a['memories_saved'] ?? 0}'),
          _StatRow('Events Extracted', '${a['events_extracted'] ?? 0}'),
          _StatRow('Highlights Created', '${a['highlights_created'] ?? 0}'),
        ]),
      ],
    );
  }

  String _formatDuration(double secs) {
    final m = (secs / 60).floor();
    final s = (secs % 60).round();
    return '$m min ${s}s';
  }

  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Coaching Tab ──────────────────────────────────────────────────────────────
class _CoachingTab extends StatelessWidget {
  final Map<String, dynamic>? report;
  final bool loading;
  final String? error;
  const _CoachingTab({required this.report, required this.loading, required this.error});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Generating coaching report…')]));
    if (error != null || report == null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.school_outlined, size: 48), SizedBox(height: 12), Text(error ?? 'Not available')]));
    final r = report!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (r['report_text'] != null)
          _SectionCard(title: '📋 Summary', children: [
            Text(r['report_text'] as String, style: const TextStyle(height: 1.5)),
          ]),
        if (r['tone_summary'] != null) ...[
          const SizedBox(height: 12),
          _SectionCard(title: '🗣️ Tone', children: [
            Text(r['tone_summary'] as String),
            if (r['engagement_trend'] != null)
              _StatRow('Engagement Trend', _capitalize('${r['engagement_trend']}')),
          ]),
        ],
        // fl_chart Radar — Conversational Tone Radar
        if (r['tone_aggression'] != null ||
            r['tone_empathy'] != null ||
            r['tone_analytical'] != null) ...[
          const SizedBox(height: 12),
          _SectionCard(title: '🎯 Conversational Tone Radar', children: [
            SizedBox(
              height: 200,
              child: _ToneRadarChart(
                aggression: (r['tone_aggression'] as num? ?? 5).toDouble(),
                empathy: (r['tone_empathy'] as num? ?? 5).toDouble(),
                analytical: (r['tone_analytical'] as num? ?? 5).toDouble(),
                confidence: (r['tone_confidence'] as num? ?? 5).toDouble(),
                clarity: (r['tone_clarity'] as num? ?? 5).toDouble(),
              ),
            ),
          ]),
        ],
        const SizedBox(height: 12),
        if (_hasList(r, 'key_topics'))
          _ChipSection(title: '🏷️ Key Topics', items: _castList(r['key_topics']), color: Colors.blue),
        if (_hasList(r, 'action_items')) ...[
          const SizedBox(height: 12),
          _BulletSection(title: '✅ Action Items', items: _castList(r['action_items'])),
        ],
        if (_hasList(r, 'suggestions')) ...[
          const SizedBox(height: 12),
          _BulletSection(title: '💡 Suggestions', items: _castList(r['suggestions'])),
        ],
        if (_hasList(r, 'strengths')) ...[
          const SizedBox(height: 12),
          _ChipSection(title: '💪 Strengths', items: _castList(r['strengths']), color: Colors.green),
        ],
        if (_hasList(r, 'filler_words')) ...[
          const SizedBox(height: 12),
          _ChipSection(title: '⚠️ Filler Words (${r['filler_word_count'] ?? 0})', items: _castList(r['filler_words']), color: Colors.orange),
        ],
        const SizedBox(height: 12),
        if (r['user_talk_pct'] != null)
          _SectionCard(title: '📊 Talk Ratio', children: [
            _TalkRatioBar(
              userPct: (r['user_talk_pct'] as num).toDouble(),
              othersPct: (r['others_talk_pct'] as num? ?? 0).toDouble(),
            ),
          ]),
        const SizedBox(height: 32),
      ],
    );
  }

  bool _hasList(Map m, String key) => m[key] is List && (m[key] as List).isNotEmpty;
  List<String> _castList(dynamic l) => (l as List).map((e) => e.toString()).toList();
  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Shared widgets ────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ChipSection extends StatelessWidget {
  final String title;
  final List<String> items;
  final Color color;
  const _ChipSection({required this.title, required this.items, required this.color});
  @override
  Widget build(BuildContext context) {
    return _SectionCard(title: title, children: [
      Wrap(
        spacing: 8, runSpacing: 8,
        children: items.map((i) => Chip(
          label: Text(i),
          backgroundColor: color.withOpacity(0.15),
          labelStyle: TextStyle(color: color, fontWeight: FontWeight.w500),
          side: BorderSide(color: color.withOpacity(0.3)),
        )).toList(),
      ),
    ]);
  }
}

class _BulletSection extends StatelessWidget {
  final String title;
  final List<String> items;
  const _BulletSection({required this.title, required this.items});
  @override
  Widget build(BuildContext context) {
    return _SectionCard(title: title, children: items.map((i) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
        Expanded(child: Text(i)),
      ]),
    )).toList());
  }
}

class _TalkRatioBar extends StatelessWidget {
  final double userPct;
  final double othersPct;
  const _TalkRatioBar({required this.userPct, required this.othersPct});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Row(children: [
          Flexible(flex: userPct.round(), child: Container(height: 16, color: Colors.blue.withOpacity(0.7))),
          Flexible(flex: othersPct.round(), child: Container(height: 16, color: Colors.purple.withOpacity(0.7))),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        _LegendDot(color: Colors.blue, label: 'You ${userPct.toStringAsFixed(0)}%'),
        const SizedBox(width: 16),
        _LegendDot(color: Colors.purple, label: 'Others ${othersPct.toStringAsFixed(0)}%'),
      ]),
    ]);
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ]);
  }
}

// ── fl_chart: Sentiment Line Chart ───────────────────────────────────────────
class _SentimentLineChart extends StatelessWidget {
  final List trend;
  const _SentimentLineChart({required this.trend});

  @override
  Widget build(BuildContext context) {
    if (trend.isEmpty) return const SizedBox();

    final spots = <FlSpot>[];
    for (int i = 0; i < trend.length; i++) {
      final item = trend[i] as Map<String, dynamic>;
      final score = (item['score'] as num?)?.toDouble() ?? 0.0;
      spots.add(FlSpot(i.toDouble(), score.clamp(-1.0, 1.0)));
    }

    return LineChart(
      LineChartData(
        minY: -1,
        maxY: 1,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white12,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.blueAccent,
            barWidth: 2,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) {
                final c = spot.y > 0.2
                    ? Colors.green
                    : spot.y < -0.2
                        ? Colors.red
                        : Colors.grey;
                return FlDotCirclePainter(radius: 3, color: c, strokeWidth: 0);
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blueAccent.withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }
}

// ── fl_chart: Conversational Tone Radar Chart ─────────────────────────────────
class _ToneRadarChart extends StatelessWidget {
  final double aggression;
  final double empathy;
  final double analytical;
  final double confidence;
  final double clarity;

  const _ToneRadarChart({
    required this.aggression,
    required this.empathy,
    required this.analytical,
    required this.confidence,
    required this.clarity,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: RadarChart(
            RadarChartData(
              dataSets: [
                RadarDataSet(
                  fillColor: const Color(0xFF6366F1).withOpacity(0.2),
                  borderColor: const Color(0xFF6366F1),
                  borderWidth: 2,
                  entryRadius: 4,
                  dataEntries: [
                    RadarEntry(value: aggression),
                    RadarEntry(value: empathy),
                    RadarEntry(value: analytical),
                    RadarEntry(value: confidence),
                    RadarEntry(value: clarity),
                  ],
                ),
              ],
              radarBackgroundColor: Colors.transparent,
              borderData: FlBorderData(show: false),
              radarBorderData: const BorderSide(color: Colors.white12),
              gridBorderData: const BorderSide(color: Colors.white12, width: 1),
              tickCount: 5,
              ticksTextStyle: const TextStyle(color: Colors.transparent, fontSize: 0),
              tickBorderData: const BorderSide(color: Colors.white10),
              titleTextStyle: const TextStyle(color: Colors.white70, fontSize: 11),
              getTitle: (index, _) {
                const titles = [
                  'Aggressive',
                  'Empathetic',
                  'Analytical',
                  'Confident',
                  'Clear',
                ];
                return RadarChartTitle(
                  text: titles[index],
                  positionPercentageOffset: 0.1,
                );
              },
            ),
          ),
        ),
        // Legend
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RadarLegendItem('Aggressive', aggression),
            _RadarLegendItem('Empathetic', empathy),
            _RadarLegendItem('Analytical', analytical),
            _RadarLegendItem('Confident', confidence),
            _RadarLegendItem('Clear', clarity),
          ],
        ),
      ],
    );
  }
}

class _RadarLegendItem extends StatelessWidget {
  final String label;
  final double value;
  const _RadarLegendItem(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$label: ${value.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 10, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
