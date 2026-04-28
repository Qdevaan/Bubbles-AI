import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../repositories/sessions_repository.dart';
import '../widgets/glass_morphism.dart';
import '../theme/design_tokens.dart';
import '../widgets/chat_bubble.dart';

/// Displays post-session analytics (session_analytics) and coaching report
/// (coaching_reports) for a given Live Wingman session. (schema_v2 B5 / G2)
class SessionAnalyticsScreen extends StatefulWidget {
  final String sessionId;
  final String sessionTitle;
  final int initialTab;

  const SessionAnalyticsScreen({
    super.key,
    required this.sessionId,
    required this.sessionTitle,
    this.initialTab = 0,
  });

  @override
  State<SessionAnalyticsScreen> createState() => _SessionAnalyticsScreenState();
}

class _SessionAnalyticsScreenState extends State<SessionAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _analytics;
  Map<String, dynamic>? _report;
  List<Map<String, dynamic>> _logs = [];
  bool _analyticsLoading = true;
  bool _reportLoading = true;
  bool _logsLoading = true;
  String? _analyticsError;
  String? _reportError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _fetchData();
  }

  Future<void> _fetchData() async {
    final api = context.read<ApiService>();
    final sessionsRepo = context.read<SessionsRepository>();
    final userId = AuthService.instance.currentUserId ?? '';

    // Fetch analytics
    try {
      final res = await sessionsRepo.getSessionAnalytics(widget.sessionId, userId, forceRefresh: false);
      if (mounted) setState(() { 
        _analytics = res.data; 
        _analyticsLoading = false; 
        _analyticsError = res.data == null ? 'Not yet computed' : null; 
      });
    } catch (e) {
      if (mounted) setState(() { _analyticsLoading = false; _analyticsError = 'Failed to load'; });
    }
    // Fetch coaching report (can be slow — generates on demand)
    try {
      final res = await sessionsRepo.getCoachingReport(widget.sessionId, userId, forceRefresh: false);
      if (mounted) setState(() { 
        _report = res.data; 
        _reportLoading = false; 
        _reportError = res.data == null ? 'Not available' : null; 
      });
    } catch (e) {
      if (mounted) setState(() { _reportLoading = false; _reportError = 'Failed to load'; });
    }
    // Fetch logs (transcript)
    try {
      final res = await sessionsRepo.getSessionLogs(widget.sessionId, false, userId);
      if (mounted) setState(() { _logs = res.data ?? []; _logsLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _logsLoading = false; });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MeshGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Session Report',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
              Text(
                widget.sessionTitle,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: (isDark ? Colors.white : AppColors.slate900).withOpacity(0.6),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            indicatorPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            indicator: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: isDark ? AppColors.slate400 : AppColors.slate500,
            labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13),
            tabs: const [
              Tab(text: 'Analytics'),
              Tab(text: 'Coaching'),
              Tab(text: 'Transcript'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _AnalyticsTab(analytics: _analytics, loading: _analyticsLoading, error: _analyticsError),
            _CoachingTab(report: _report, loading: _reportLoading, error: _reportError),
            _TranscriptTab(logs: _logs, loading: _logsLoading),
          ],
        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (loading) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: 12), Text('Computing analytics…', style: GoogleFonts.manrope())]));
    if (error != null || analytics == null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.bar_chart_outlined, size: 48, color: AppColors.slate500), const SizedBox(height: 12), Text(error ?? 'No data yet', style: GoogleFonts.manrope(color: AppColors.slate500))]));
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
            Text('Emotion Flow:', style: GoogleFonts.manrope(color: isDark ? AppColors.slate400 : AppColors.slate500, fontSize: 12, fontWeight: FontWeight.w600)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (loading) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: 12), Text('Generating coaching report…', style: GoogleFonts.manrope())]));
    if (error != null || report == null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.school_outlined, size: 48, color: AppColors.slate500), const SizedBox(height: 12), Text(error ?? 'Not available', style: GoogleFonts.manrope(color: AppColors.slate500))]));
    final r = report!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (r['report_text'] != null)
          _SectionCard(title: '📋 Summary', children: [
            Text(r['report_text'] as String, style: GoogleFonts.manrope(height: 1.5, fontSize: 14, color: isDark ? AppColors.slate300 : AppColors.slate600)),
          ]),
        if (r['tone_summary'] != null) ...[
          const SizedBox(height: 12),
          _SectionCard(title: '🗣️ Tone', children: [
            Text(r['tone_summary'] as String, style: GoogleFonts.manrope(fontSize: 14, color: isDark ? AppColors.slate300 : AppColors.slate600)),
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

// ── Transcript Tab ────────────────────────────────────────────────────────────
class _TranscriptTab extends StatelessWidget {
  final List<Map<String, dynamic>> logs;
  final bool loading;
  const _TranscriptTab({required this.logs, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (logs.isEmpty) return Center(child: Text('No transcript available', style: GoogleFonts.manrope(color: AppColors.slate500)));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        final role = (log['role'] as String? ?? 'others').toLowerCase();
        final content = log['content'] as String? ?? '';
        final isUser = role == 'user';
        final isAI = role == 'assistant' || role == 'llm';
        final String displayName = _getDisplayName(role, log['speaker_label']);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ChatBubble(
            text: content,
            isUser: isUser,
            isAI: isAI,
            speakerLabel: isUser ? null : displayName,
          ),
        );
      },
    );
  }

  String _getDisplayName(String role, dynamic label) {
    if (role == 'user') return 'You';
    if (role == 'assistant' || role == 'llm') return 'Bubbles AI';
    if (label != null) return label.toString();
    return 'Other';
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
            const SizedBox(height: 12),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.manrope(color: isDark ? AppColors.slate400 : AppColors.slate500, fontSize: 13)),
          Text(value, style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13, color: isDark ? Colors.white : AppColors.slate900)),
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
          labelStyle: GoogleFonts.manrope(fontSize: 12, color: color, fontWeight: FontWeight.w700),
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
        Text('• ', style: GoogleFonts.manrope(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
        Expanded(child: Text(i, style: GoogleFonts.manrope(fontSize: 13, height: 1.4))),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: RadarChart(
            RadarChartData(
              dataSets: [
                RadarDataSet(
                  fillColor: colorScheme.primary.withOpacity(0.2),
                  borderColor: colorScheme.primary,
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
              tickBorderData: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
              titleTextStyle: GoogleFonts.manrope(color: isDark ? AppColors.slate400 : AppColors.slate500, fontSize: 11, fontWeight: FontWeight.w600),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ${value.toStringAsFixed(1)}',
            style: GoogleFonts.manrope(fontSize: 11, color: isDark ? AppColors.slate300 : AppColors.slate600, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
