import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/gamification_provider.dart';
import '../theme/design_tokens.dart';
import '../widgets/animated_background.dart';
import '../widgets/skeleton_loader.dart';

/// Full Game Center — replaces the old QuestsScreen.
/// Shows XP ring, streak, daily quests, achievements, AI coach, and XP feed.
class GameCenterScreen extends StatefulWidget {
  const GameCenterScreen({super.key});

  @override
  State<GameCenterScreen> createState() => _GameCenterScreenState();
}

class _GameCenterScreenState extends State<GameCenterScreen>
    with TickerProviderStateMixin {
  late AnimationController _heroCtrl;
  late Animation<double> _heroScale;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _heroCtrl = AnimationController(
      vsync: this,
      duration: AppDurations.celebration,
    );
    _heroScale = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _heroCtrl, curve: Curves.elasticOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<GamificationProvider>(context, listen: false).init();
      _heroCtrl.forward();
    });
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Stack(
        children: [
          AnimatedAmbientBackground(
            isDark: isDark,
            scrollController: _scrollCtrl,
          ),
          SafeArea(
            child: Consumer<GamificationProvider>(
              builder: (context, gp, _) {
                return Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(Icons.arrow_back,
                                color:
                                    isDark ? Colors.white : Colors.black87),
                          ),
                          Expanded(
                            child: Text(
                              'Game Center',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.manrope(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.slate900,
                              ),
                            ),
                          ),
                          // Skill tier badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.levelBadge.withAlpha(30),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                              border: Border.all(
                                  color: AppColors.levelBadge.withAlpha(80)),
                            ),
                            child: Text(
                              '${gp.skillTierEmoji} ${gp.skillTierLabel}',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.levelBadge,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Scrollable content
                    Expanded(
                      child: gp.profileLoading
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: SkeletonCardGroup(count: 4),
                            )
                          : CustomScrollView(
                              controller: _scrollCtrl,
                              slivers: [
                                // ── Hero: XP Ring ──
                                SliverToBoxAdapter(
                                  child: _buildHeroSection(
                                      context, gp, isDark, primary),
                                ),

                                // ── Streak Section ──
                                SliverToBoxAdapter(
                                  child: _buildStreakSection(
                                      context, gp, isDark),
                                ),

                                // ── AI Coach Card ──
                                if (gp.aiCoachingTip != null)
                                  SliverToBoxAdapter(
                                    child: _buildAiCoachCard(
                                        context, gp, isDark),
                                  ),

                                // ── Daily Quests Header ──
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        20, 20, 20, 8),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Daily Quests',
                                          style: GoogleFonts.manrope(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? Colors.white
                                                : AppColors.slate900,
                                          ),
                                        ),
                                        if (gp.timeUntilReset != null)
                                          Container(
                                            padding: const EdgeInsets
                                                .symmetric(
                                                horizontal: 10,
                                                vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? AppColors.glassWhite
                                                  : Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AppRadius.full),
                                            ),
                                            child: Text(
                                              'Resets in ${_formatDuration(gp.timeUntilReset!)}',
                                              style: GoogleFonts.manrope(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: isDark
                                                    ? AppColors.slate400
                                                    : AppColors.slate500,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),

                                // ── Quest Cards ──
                                if (gp.questsLoading)
                                  const SliverToBoxAdapter(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 16),
                                      child: SkeletonCardGroup(count: 3),
                                    ),
                                  )
                                else if (gp.dailyQuests.isEmpty)
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Center(
                                        child: Text(
                                          'No quests available today.',
                                          style: GoogleFonts.manrope(
                                            color: isDark
                                                ? AppColors.slate500
                                                : AppColors.slate400,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (ctx, i) => Padding(
                                        padding:
                                            const EdgeInsets.fromLTRB(
                                                16, 0, 16, 8),
                                        child: _QuestCard(
                                          quest: gp.dailyQuests[i],
                                          isDark: isDark,
                                          primary: primary,
                                        ),
                                      ),
                                      childCount: gp.dailyQuests.length,
                                    ),
                                  ),

                                // ── Achievements Gallery ──
                                if (gp.badges.isNotEmpty)
                                  SliverToBoxAdapter(
                                    child: _buildAchievementsSection(
                                        context, gp, isDark),
                                  ),

                                // ── XP Activity Feed ──
                                if (gp.recentXp.isNotEmpty)
                                  SliverToBoxAdapter(
                                    child: _buildXpFeed(
                                        context, gp, isDark),
                                  ),

                                // ── Stats Summary ──
                                SliverToBoxAdapter(
                                  child: _buildStatsSection(
                                      context, gp, isDark),
                                ),

                                const SliverToBoxAdapter(
                                    child: SizedBox(height: 40)),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero Section ──────────────────────────────────────────────────────────
  Widget _buildHeroSection(BuildContext context, GamificationProvider gp,
      bool isDark, Color primary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: AnimatedBuilder(
        animation: _heroScale,
        builder: (_, child) => Transform.scale(
          scale: _heroScale.value,
          child: child,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppColors.glassWhite : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            border: Border.all(
              color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: primary.withAlpha(isDark ? 30 : 15),
                blurRadius: 24,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Column(
            children: [
              // Large XP ring
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Ring
                    CustomPaint(
                      size: const Size(120, 120),
                      painter: _LargeRingPainter(
                        progress: gp.xpProgressPct,
                        ringColor: primary,
                        trackColor: isDark
                            ? Colors.white.withAlpha(15)
                            : Colors.grey.shade200,
                      ),
                    ),
                    // Level text
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'LEVEL',
                          style: GoogleFonts.manrope(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: isDark
                                ? AppColors.slate500
                                : AppColors.slate400,
                          ),
                        ),
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [primary, AppColors.levelBadge],
                          ).createShader(bounds),
                          child: Text(
                            '${gp.level}',
                            style: GoogleFonts.manrope(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // XP counter
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star_rounded,
                      color: AppColors.xpGold, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '${gp.totalXp} XP',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.slate900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // XP bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: gp.xpProgressPct.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: isDark
                      ? Colors.white.withAlpha(15)
                      : Colors.grey.shade200,
                  color: primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${gp.xpToNextLevel} XP to Level ${gp.level + 1}',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: isDark ? AppColors.slate500 : AppColors.slate400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Streak Section ────────────────────────────────────────────────────────
  Widget _buildStreakSection(
      BuildContext context, GamificationProvider gp, bool isDark) {
    final weekDays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final activity = gp.weekActivity;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.glassWhite : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(
            color: gp.isStreakHot
                ? AppColors.streakFire.withAlpha(60)
                : (isDark ? AppColors.glassBorder : Colors.grey.shade200),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  gp.currentStreak > 0 ? '🔥' : '💤',
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(width: 8),
                Text(
                  '${gp.currentStreak}-Day Streak',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: gp.isStreakHot
                        ? AppColors.streakFire
                        : (isDark ? Colors.white : AppColors.slate900),
                  ),
                ),
                const Spacer(),
                if (gp.streakFreezes > 0)
                  Text(
                    '❄️ ×${gp.streakFreezes}',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.slate400 : AppColors.slate500,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // Week dots
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (i) {
                final isToday = i == gp.todayWeekdayIndex;
                final isActive = activity[i];
                return Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: isToday ? 32 : 28,
                      height: isToday ? 32 : 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive
                            ? (gp.isStreakHot
                                ? AppColors.streakFire
                                : Theme.of(context).colorScheme.primary)
                            : (isDark
                                ? Colors.white.withAlpha(10)
                                : Colors.grey.shade100),
                        border: isToday
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2)
                            : null,
                        boxShadow: isActive && gp.isStreakHot
                            ? [
                                BoxShadow(
                                  color: AppColors.streakFire.withAlpha(60),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: isActive
                            ? const Icon(Icons.check,
                                size: 14, color: Colors.white)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      weekDays[i],
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight:
                            isToday ? FontWeight.w800 : FontWeight.w500,
                        color: isToday
                            ? (isDark ? Colors.white : AppColors.slate900)
                            : (isDark
                                ? AppColors.slate500
                                : AppColors.slate400),
                      ),
                    ),
                  ],
                );
              }),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Best: ${gp.longestStreak} days',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: isDark ? AppColors.slate500 : AppColors.slate400,
                  ),
                ),
                Text(
                  gp.isStreakHot ? '🔥 On fire!' : 'Keep going!',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: gp.isStreakHot
                        ? AppColors.streakFire
                        : (isDark ? AppColors.slate400 : AppColors.slate500),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── AI Coach Card ─────────────────────────────────────────────────────────
  Widget _buildAiCoachCard(
      BuildContext context, GamificationProvider gp, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    AppColors.levelBadge.withAlpha(20),
                    AppColors.glassWhite,
                  ]
                : [
                    AppColors.levelBadge.withAlpha(10),
                    Colors.white,
                  ],
          ),
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(
            color: AppColors.levelBadge.withAlpha(40),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('✨', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  'AI Coach',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                ),
                const Spacer(),
                if (gp.weeklyScore != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (gp.scoreDelta ?? 0) >= 0
                          ? AppColors.success.withAlpha(20)
                          : AppColors.error.withAlpha(20),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      '${(gp.scoreDelta ?? 0) >= 0 ? '⬆️' : '⬇️'} ${gp.weeklyScore!.toStringAsFixed(1)}/10',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: (gp.scoreDelta ?? 0) >= 0
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              gp.aiCoachingTip ?? '',
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.5,
                color: isDark ? AppColors.slate300 : AppColors.slate600,
              ),
            ),
            if (gp.focusAreas.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: gp.focusAreas.map((area) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.levelBadge.withAlpha(20),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      area.replaceAll('_', ' '),
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.levelBadge,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Achievements Gallery ──────────────────────────────────────────────────
  Widget _buildAchievementsSection(
      BuildContext context, GamificationProvider gp, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Achievements',
            style: GoogleFonts.manrope(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.slate900,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: gp.badges.length,
              itemBuilder: (_, i) {
                final badge = gp.badges[i];
                return Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.glassWhite : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.achievementGlow.withAlpha(60),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.achievementGlow.withAlpha(20),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        badge['icon'] as String? ?? '🏆',
                        style: const TextStyle(fontSize: 28),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          badge['title'] as String? ?? '',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.slate300
                                : AppColors.slate600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── XP Activity Feed ──────────────────────────────────────────────────────
  Widget _buildXpFeed(
      BuildContext context, GamificationProvider gp, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent XP',
            style: GoogleFonts.manrope(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.slate900,
            ),
          ),
          const SizedBox(height: 10),
          ...gp.recentXp.take(5).map((tx) {
            final amount = (tx['amount'] as num?)?.toInt() ?? 0;
            final source = tx['source_type'] as String? ?? '';
            final desc = tx['description'] as String? ?? _sourceLabel(source);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.xpGold.withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _sourceEmoji(source),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      desc,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: isDark ? AppColors.slate300 : AppColors.slate600,
                      ),
                    ),
                  ),
                  Text(
                    '+$amount',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.xpGold,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Stats Summary ─────────────────────────────────────────────────────────
  Widget _buildStatsSection(
      BuildContext context, GamificationProvider gp, bool isDark) {
    final items = [
      ('Sessions', '${gp.stats['total_sessions'] ?? 0}', Icons.mic),
      ('Questions', '${gp.stats['total_consultant_questions'] ?? 0}', Icons.forum),
      ('Entities', '${gp.stats['total_entities'] ?? 0}', Icons.person),
      ('Quests Done', '${gp.stats['total_quests_completed'] ?? 0}', Icons.emoji_events),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stats',
            style: GoogleFonts.manrope(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.slate900,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: items.map((item) {
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.glassWhite : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? AppColors.glassBorder
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(item.$3,
                          size: 18,
                          color: isDark
                              ? AppColors.slate400
                              : AppColors.slate500),
                      const SizedBox(height: 6),
                      Text(
                        item.$2,
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : AppColors.slate900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.$1,
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          color: isDark
                              ? AppColors.slate500
                              : AppColors.slate400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _sourceEmoji(String source) {
    switch (source) {
      case 'session_complete':
        return '🎙️';
      case 'consultant_qa':
        return '💬';
      case 'entity_extraction':
        return '🧠';
      case 'streak_bonus':
        return '🔥';
      case 'quest_complete':
        return '⭐';
      case 'achievement_unlock':
        return '🏆';
      default:
        return '✨';
    }
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'session_complete':
        return 'Session completed';
      case 'consultant_qa':
        return 'Asked consultant';
      case 'entity_extraction':
        return 'New entity discovered';
      case 'streak_bonus':
        return 'Streak bonus';
      case 'quest_complete':
        return 'Quest completed';
      case 'achievement_unlock':
        return 'Achievement unlocked';
      default:
        return source.replaceAll('_', ' ');
    }
  }
}

// ── Quest Card ──────────────────────────────────────────────────────────────

class _QuestCard extends StatelessWidget {
  final Map<String, dynamic> quest;
  final bool isDark;
  final Color primary;

  const _QuestCard({
    required this.quest,
    required this.isDark,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final title = quest['title'] as String? ?? 'Quest';
    final xpReward = (quest['xp_reward'] as num?)?.toInt() ?? 0;
    final target = (quest['target'] as num?)?.toInt() ?? 1;
    int progress = (quest['progress'] as num?)?.toInt() ?? 0;
    final isCompleted = quest['is_completed'] == true;
    if (progress > target) progress = target;
    final progressPct = target > 0 ? progress / target : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? (isCompleted
                ? AppColors.success.withAlpha(10)
                : AppColors.glassWhite)
            : (isCompleted ? AppColors.success.withAlpha(8) : Colors.white),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(
          color: isCompleted
              ? AppColors.success.withAlpha(60)
              : (isDark ? AppColors.glassBorder : Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          // Mini progress ring
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progressPct.clamp(0.0, 1.0),
                  strokeWidth: 3,
                  backgroundColor: isDark
                      ? Colors.white.withAlpha(10)
                      : Colors.grey.shade100,
                  color: isCompleted ? AppColors.success : primary,
                ),
                Icon(
                  isCompleted ? Icons.check_circle : Icons.star_rounded,
                  size: 20,
                  color: isCompleted ? AppColors.success : AppColors.xpGold,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.slate900,
                    decoration:
                        isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '+$xpReward XP',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isCompleted
                        ? AppColors.success
                        : AppColors.xpGold,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$progress/$target',
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: isCompleted
                  ? AppColors.success
                  : (isDark ? AppColors.slate400 : AppColors.slate500),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Large ring painter ──────────────────────────────────────────────────────

class _LargeRingPainter extends CustomPainter {
  final double progress;
  final Color ringColor;
  final Color trackColor;

  _LargeRingPainter({
    required this.progress,
    required this.ringColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 6;

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );

    // Progress
    if (progress > 0) {
      final sweepAngle = 2 * pi * progress.clamp(0.0, 1.0);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        sweepAngle,
        false,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_LargeRingPainter old) =>
      old.progress != progress || old.ringColor != ringColor;
}
