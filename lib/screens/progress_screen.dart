// Purpose: Progress screen — visualises the user's XP history, skill growth, and session frequency over time.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/help_content.dart';
import '../models/dashboard_models.dart';
import '../providers/dashboard_provider.dart';
import '../routes/app_routes.dart';
import '../theme/design_tokens.dart';
import '../widgets/help_sheet.dart';
import '../widgets/skeleton_loader.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  DateTime _lastRangeChange = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<DashboardProvider>();
      if (!provider.hasData) {
        provider.load();
      }
    });
  }

  Future<void> _refresh() => context.read<DashboardProvider>().load();

  void _setRange(String r) {
    final now = DateTime.now();
    if (now.difference(_lastRangeChange) < const Duration(milliseconds: 350)) {
      return; // debounce against 429s
    }
    _lastRangeChange = now;
    context.read<DashboardProvider>().setRange(r);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Progress',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppColors.slate900,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : AppColors.slate900,
        ),
        actions: const [
          HelpIconButton(screen: HelpScreen.progress),
        ],
      ),
      body: SafeArea(
        child: Consumer<DashboardProvider>(
          builder: (context, p, _) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _RangeSegmented(
                    current: p.range,
                    onChanged: _setRange,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 16),
                  if (p.state == DashboardLoadState.loading && !p.hasData)
                    const SkeletonDropdownForm()
                  else if (p.state == DashboardLoadState.error && !p.hasData)
                    _ErrorState(
                        message: p.error ?? 'Error', onRetry: _refresh)
                  else if (p.data != null) ...[
                    _SnapshotStrip(summary: p.data!.summary, isDark: isDark),
                    const SizedBox(height: 18),
                    _SummaryGrid(
                      summary: p.data!.summary,
                      range: p.range,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 22),
                    _SeriesSection(
                      data: p.data!,
                      isDark: isDark,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RangeSegmented extends StatelessWidget {
  const _RangeSegmented({
    required this.current,
    required this.onChanged,
    required this.isDark,
  });

  final String current;
  final ValueChanged<String> onChanged;
  final bool isDark;

  static const _options = ['30d', '90d', '365d'];
  static const _labels = {'30d': '30 d', '90d': '90 d', '365d': '1 yr'};

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.slate100,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        children: [
          for (final r in _options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(r),
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: r == current
                        ? AppColors.primary
                        : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(AppRadius.full),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _labels[r]!,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: r == current
                          ? Colors.white
                          : (isDark
                              ? AppColors.slate300
                              : AppColors.slate600),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SnapshotStrip extends StatelessWidget {
  const _SnapshotStrip({required this.summary, required this.isDark});

  final DashboardSummary summary;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color:
              isDark ? AppColors.glassBorder : AppColors.slate200,
        ),
      ),
      child: Row(
        children: [
          _SnapshotChip(
            icon: Icons.local_fire_department_rounded,
            color: AppColors.streakFire,
            label: 'Streak',
            value: '${summary.currentStreak}d',
            isDark: isDark,
          ),
          _Divider(isDark: isDark),
          _SnapshotChip(
            icon: Icons.workspace_premium_rounded,
            color: AppColors.xpGold,
            label: 'Level',
            value: '${summary.level}',
            isDark: isDark,
          ),
          _Divider(isDark: isDark),
          GestureDetector(
            onTap: () => Navigator.of(context)
                .pushNamed(AppRoutes.drills),
            child: _SnapshotChip(
              icon: Icons.style_rounded,
              color: AppColors.primary,
              label: 'Due',
              value: '${summary.dueDrillCount}',
              isDark: isDark,
            ),
          ),
          _Divider(isDark: isDark),
          _SnapshotChip(
            icon: Icons.school_rounded,
            color: AppColors.success,
            label: 'Mastery',
            value: summary.drillMasteryPct == null
                ? '—'
                : '${summary.drillMasteryPct}%',
            isDark: isDark,
          ),
        ],
      ),
    );
  }
}

class _SnapshotChip extends StatelessWidget {
  const _SnapshotChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.isDark,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: isDark ? Colors.white : AppColors.slate900,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 10.5,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.slate400 : AppColors.slate500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.isDark});
  final bool isDark;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: isDark ? AppColors.glassBorder : AppColors.slate200,
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.summary,
    required this.range,
    required this.isDark,
  });

  final DashboardSummary summary;
  final String range;
  final bool isDark;

  static const _rangeLabel = {
    '30d': 'vs previous 30 d',
    '90d': 'vs previous 90 d',
    '365d': 'vs previous 1 yr',
  };

  @override
  Widget build(BuildContext context) {
    final sub = _rangeLabel[range] ?? 'vs previous window';
    final cards = <Widget>[
      _SummaryCard(
        title: 'XP earned',
        value: summary.totalXp.current.toInt().toString(),
        delta: summary.totalXp.deltaPct,
        sub: sub,
        invertDelta: false,
        isDark: isDark,
      ),
      _SummaryCard(
        title: 'Sessions',
        value: summary.sessions.current.toInt().toString(),
        delta: summary.sessions.deltaPct,
        sub: sub,
        invertDelta: false,
        isDark: isDark,
      ),
      _SummaryCard(
        title: 'Mistakes',
        value: summary.mistakes.current.toInt().toString(),
        delta: summary.mistakes.deltaPct,
        sub: sub,
        invertDelta: true, // fewer mistakes = good
        isDark: isDark,
      ),
      _SummaryCard(
        title: 'Avg sentiment',
        value: summary.avgSentiment.current.toDouble().toStringAsFixed(1),
        delta: summary.avgSentiment.deltaPct,
        sub: sub,
        invertDelta: false,
        isDark: isDark,
      ),
      _SummaryCard(
        title: 'Talk time',
        value:
            '${summary.talkTimeMinutes.current.toDouble().toStringAsFixed(1)} min',
        delta: summary.talkTimeMinutes.deltaPct,
        sub: sub,
        invertDelta: false,
        isDark: isDark,
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.45,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      children: cards,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.delta,
    required this.sub,
    required this.invertDelta,
    required this.isDark,
  });

  final String title;
  final String value;
  final double? delta;
  final String sub;
  final bool invertDelta;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color:
              isDark ? AppColors.glassBorder : AppColors.slate200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: isDark ? AppColors.slate400 : AppColors.slate500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppColors.slate900,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              _DeltaPill(delta: delta, invertDelta: invertDelta),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  sub,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.slate500
                        : AppColors.slate400,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeltaPill extends StatelessWidget {
  const _DeltaPill({required this.delta, required this.invertDelta});
  final double? delta;
  final bool invertDelta;

  @override
  Widget build(BuildContext context) {
    if (delta == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.slate500.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          '—',
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.slate500,
          ),
        ),
      );
    }
    final positive = delta! > 0;
    final isGood = invertDelta ? !positive : positive;
    final color =
        delta == 0 ? AppColors.slate500 : (isGood ? AppColors.success : AppColors.error);
    final arrow = delta == 0 ? '·' : (positive ? '▲' : '▼');
    final pctText = '${delta!.abs().toStringAsFixed(1)}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        '$arrow $pctText',
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _SeriesSection extends StatelessWidget {
  const _SeriesSection({required this.data, required this.isDark});
  final DashboardResponse data;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final s = data.series;
    return Column(
      children: [
        _SparkCard(
          title: 'XP',
          buckets: s.xp,
          color: AppColors.xpGold,
          granularity: data.granularity,
          isDark: isDark,
        ),
        const SizedBox(height: 12),
        _SparkCard(
          title: 'Sessions',
          buckets: s.sessions,
          color: AppColors.primary,
          granularity: data.granularity,
          bars: true,
          isDark: isDark,
        ),
        const SizedBox(height: 12),
        _SparkCard(
          title: 'Mistakes',
          buckets: s.mistakes,
          color: AppColors.error,
          granularity: data.granularity,
          bars: true,
          isDark: isDark,
        ),
        const SizedBox(height: 12),
        _SparkCard(
          title: 'Avg sentiment',
          buckets: s.sentiment,
          color: AppColors.accent,
          granularity: data.granularity,
          allowNullGaps: true,
          isDark: isDark,
        ),
        const SizedBox(height: 12),
        _SparkCard(
          title: 'Talk time (min)',
          buckets: s.talkTime,
          color: AppColors.purple,
          granularity: data.granularity,
          isDark: isDark,
        ),
      ],
    );
  }
}

class _SparkCard extends StatelessWidget {
  const _SparkCard({
    required this.title,
    required this.buckets,
    required this.color,
    required this.granularity,
    required this.isDark,
    this.bars = false,
    this.allowNullGaps = false,
  });

  final String title;
  final List<DashboardBucket> buckets;
  final Color color;
  final String granularity;
  final bool isDark;
  final bool bars;
  final bool allowNullGaps;

  @override
  Widget build(BuildContext context) {
    final hasData = buckets.any((b) => b.value != null && b.value! > 0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color:
              isDark ? AppColors.glassBorder : AppColors.slate200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
              const Spacer(),
              Text(
                _granularityLabel(granularity),
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.slate500
                      : AppColors.slate400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 70,
            child: hasData
                ? (bars
                    ? _BarSpark(
                        buckets: buckets,
                        color: color,
                      )
                    : _LineSpark(
                        buckets: buckets,
                        color: color,
                        allowGaps: allowNullGaps,
                      ))
                : Center(
                    child: Text(
                      'No data yet',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.slate500
                            : AppColors.slate400,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static String _granularityLabel(String g) => switch (g) {
        'daily' => 'daily',
        'weekly' => 'weekly',
        'monthly' => 'monthly',
        _ => g,
      };
}

class _LineSpark extends StatelessWidget {
  const _LineSpark({
    required this.buckets,
    required this.color,
    required this.allowGaps,
  });

  final List<DashboardBucket> buckets;
  final Color color;
  final bool allowGaps;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (var i = 0; i < buckets.length; i++) {
      final v = buckets[i].value;
      if (v == null) {
        if (!allowGaps) {
          spots.add(FlSpot(i.toDouble(), 0));
        }
        // else: skip, fl_chart will draw a gap between segments
        continue;
      }
      spots.add(FlSpot(i.toDouble(), v.toDouble()));
    }
    if (spots.isEmpty) return const SizedBox.shrink();
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        minY: 0,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarSpark extends StatelessWidget {
  const _BarSpark({required this.buckets, required this.color});
  final List<DashboardBucket> buckets;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < buckets.length; i++) {
      final v = buckets[i].value?.toDouble() ?? 0;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: v,
              color: color,
              width: 6,
              borderRadius: BorderRadius.circular(2),
            ),
          ],
        ),
      );
    }
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        barGroups: groups,
        alignment: BarChartAlignment.spaceBetween,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, color: AppColors.error, size: 48),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              color: isDark ? AppColors.slate300 : AppColors.slate600,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => onRetry(),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

// Reserved for future axis labels.
// ignore: unused_element
String _fmt(DateTime d, String granularity) {
  switch (granularity) {
    case 'monthly':
      return DateFormat.yMMM().format(d);
    case 'weekly':
      return 'wk ${DateFormat('MM-dd').format(d)}';
    default:
      return DateFormat('MM-dd').format(d);
  }
}
