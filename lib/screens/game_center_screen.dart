import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/gamification_provider.dart';
import '../services/auth_service.dart';
import '../services/sessions_service.dart';
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
  bool _milestoneDialogOpen = false;

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

  Future<void> _maybeShowMilestoneDialog(
      BuildContext context, GamificationProvider gp) async {
    if (_milestoneDialogOpen) return;
    if (gp.newlyUnlockedBadges.isEmpty) return;
    if (!mounted) return;

    _milestoneDialogOpen = true;
    HapticFeedback.heavyImpact();

    while (mounted && gp.newlyUnlockedBadges.isNotEmpty) {
      final badge = gp.newlyUnlockedBadges.first;
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Milestone',
        barrierColor: Colors.black.withAlpha(140),
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) =>
            _MilestoneDialog(badge: badge),
        transitionBuilder: (_, anim, __, child) {
          final curved =
              CurvedAnimation(parent: anim, curve: Curves.elasticOut);
          return ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1).animate(curved),
            child: FadeTransition(opacity: anim, child: child),
          );
        },
      );
      gp.acknowledgeBadge(badge['id'] as String);
    }

    _milestoneDialogOpen = false;
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
                if (gp.newlyUnlockedBadges.isNotEmpty &&
                    !_milestoneDialogOpen) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _maybeShowMilestoneDialog(context, gp);
                  });
                }
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

                                // ── Rewards Shop ──
                                SliverToBoxAdapter(
                                  child: _buildRewardsSection(
                                      context, gp, isDark),
                                ),

                                // ── Achievements Gallery ──
                                if (gp.badges.isNotEmpty)
                                  SliverToBoxAdapter(
                                    child: _buildAchievementsSection(
                                        context, gp, isDark),
                                  ),

                                // ── Leaderboard ──
                                SliverToBoxAdapter(
                                  child: _buildLeaderboardSection(
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

  // ── Rewards Shop ──────────────────────────────────────────────────────────
  Widget _buildRewardsSection(
      BuildContext context, GamificationProvider gp, bool isDark) {
    if (gp.rewardsLoading && gp.rewards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Container(
          height: 80,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(),
        ),
      );
    }
    if (gp.rewards.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Rewards Shop',
                style: GoogleFonts.manrope(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.xpGold.withAlpha(isDark ? 40 : 30),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded,
                        size: 14, color: AppColors.xpGold),
                    const SizedBox(width: 4),
                    Text(
                      '${gp.xpBalance} XP',
                      style: GoogleFonts.manrope(
                        fontSize: 12, fontWeight: FontWeight.w800,
                        color: AppColors.xpGold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: gp.rewards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _RewardCard(
                reward: gp.rewards[i],
                balance: gp.xpBalance,
                isDark: isDark,
                primary: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Leaderboard ───────────────────────────────────────────────────────────
  Widget _buildLeaderboardSection(
      BuildContext context, GamificationProvider gp, bool isDark) {
    final theme = Theme.of(context);
    final periods = const [
      ('daily', 'Today'),
      ('weekly', 'Week'),
      ('monthly', 'Month'),
      ('all', 'All-time'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Leaderboard',
                style: GoogleFonts.manrope(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: gp.leaderboardOptIn
                    ? 'Hide me from leaderboard'
                    : 'Show me on leaderboard',
                icon: Icon(
                  gp.leaderboardOptIn
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  color: gp.leaderboardOptIn
                      ? theme.colorScheme.primary
                      : AppColors.slate500,
                  size: 20,
                ),
                onPressed: () =>
                    gp.setLeaderboardOptIn(!gp.leaderboardOptIn),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: periods.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final (id, label) = periods[i];
                final selected = gp.leaderboardPeriod == id;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) {
                    if (!selected) gp.loadLeaderboard(period: id);
                  },
                  labelStyle: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : null,
                  ),
                  selectedColor: theme.colorScheme.primary,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          if (gp.leaderboardLoading && gp.leaderboardRows.isEmpty)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ))
          else if (gp.leaderboardRows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'No one on the board yet — earn some XP to lead the pack.',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: isDark ? AppColors.slate400 : AppColors.slate600,
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.glassWhite : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.xxl),
                border: Border.all(
                  color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
                ),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < gp.leaderboardRows.length; i++) ...[
                    _LeaderboardRow(
                      row: gp.leaderboardRows[i],
                      isDark: isDark,
                      primary: theme.colorScheme.primary,
                    ),
                    if (i < gp.leaderboardRows.length - 1)
                      Divider(
                        height: 1,
                        color: isDark
                            ? AppColors.glassBorder
                            : Colors.grey.shade100,
                      ),
                  ],
                ],
              ),
            ),
          if (gp.leaderboardSelf != null) ...[
            const SizedBox(height: 8),
            _SelfRankPill(self: gp.leaderboardSelf!, isDark: isDark),
          ],
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
    final reason = (quest['reason'] as String?)?.trim();
    final missionType = (quest['mission_type'] as String?) ?? 'action';
    if (progress > target) progress = target;
    final progressPct = target > 0 ? progress / target : 0.0;

    final isInteractive = !isCompleted && missionType != 'action';

    return InkWell(
      onTap: isInteractive ? () => _openMissionSheet(context, missionType) : null,
      borderRadius: BorderRadius.circular(AppRadius.xxl),
      child: Container(
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
                  isCompleted
                      ? Icons.check_circle
                      : _missionTypeIcon(missionType),
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
                if (reason != null && reason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primary.withAlpha(isDark ? 30 : 20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: primary.withAlpha(60), width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, size: 11, color: primary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            reason,
                            style: GoogleFonts.manrope(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
    ),
    );
  }

  IconData _missionTypeIcon(String type) {
    switch (type) {
      case 'question_set':
        return Icons.quiz_rounded;
      case 'conversation':
        return Icons.forum_rounded;
      default:
        return Icons.star_rounded;
    }
  }

  void _openMissionSheet(BuildContext context, String missionType) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        if (missionType == 'question_set') {
          return _QuestionSetSheet(quest: quest);
        }
        if (missionType == 'conversation') {
          return _ConversationMissionSheet(quest: quest);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ── Question Set Sheet ──────────────────────────────────────────────────────

class _QuestionSetSheet extends StatefulWidget {
  final Map<String, dynamic> quest;
  const _QuestionSetSheet({required this.quest});

  @override
  State<_QuestionSetSheet> createState() => _QuestionSetSheetState();
}

class _QuestionSetSheetState extends State<_QuestionSetSheet> {
  late final List<Map<String, dynamic>> _questions;
  late final Map<String, String> _answers;
  late final Map<String, TextEditingController> _ctrls;
  String? _submittingId;

  @override
  void initState() {
    super.initState();
    final brief = widget.quest['brief'] as Map<String, dynamic>? ?? {};
    final raw = (brief['questions'] as List?) ?? const [];
    _questions = raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final state = widget.quest['brief_state'] as Map<String, dynamic>? ?? {};
    final saved = (state['answers'] as Map?) ?? {};
    _answers = saved.map((k, v) => MapEntry(k.toString(), v.toString()));
    _ctrls = {
      for (final q in _questions)
        (q['id'] as String? ?? ''): TextEditingController(
          text: _answers[q['id']] ?? '',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit(String questionId) async {
    final answer = (_ctrls[questionId]?.text ?? '').trim();
    if (answer.isEmpty) return;

    setState(() => _submittingId = questionId);
    final gp = context.read<GamificationProvider>();
    final ok = await gp.submitQuestAnswer(
      userQuestId: widget.quest['id'] as String,
      questionId: questionId,
      answer: answer,
    );
    if (!mounted) return;
    setState(() {
      if (ok) _answers[questionId] = answer;
      _submittingId = null;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not submit answer. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final title = widget.quest['title'] as String? ?? 'Mission';
    final answered = _answers.length;
    final total = _questions.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtl) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A24) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.quiz_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontSize: 18, fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '$answered / $total',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                controller: scrollCtl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                itemCount: _questions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (_, i) {
                  final q = _questions[i];
                  final qid = q['id'] as String? ?? 'q_$i';
                  final prompt = q['prompt'] as String? ?? '';
                  final isAnswered = _answers.containsKey(qid);
                  final isBusy = _submittingId == qid;

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isAnswered
                          ? AppColors.success.withAlpha(isDark ? 18 : 12)
                          : (isDark ? AppColors.glassWhite : Colors.grey.shade50),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: isAnswered
                            ? AppColors.success.withAlpha(80)
                            : (isDark
                                ? AppColors.glassBorder
                                : Colors.grey.shade200),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Q${i + 1}',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            if (isAnswered) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.check_circle,
                                  size: 14, color: AppColors.success),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(prompt,
                            style: GoogleFonts.manrope(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _ctrls[qid],
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Your answer…',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonalIcon(
                            onPressed: isBusy ||
                                    (_ctrls[qid]?.text.trim().isEmpty ?? true)
                                ? null
                                : () => _submit(qid),
                            icon: isBusy
                                ? const SizedBox(
                                    width: 14, height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : Icon(isAnswered
                                    ? Icons.refresh
                                    : Icons.send_rounded, size: 16),
                            label: Text(isAnswered ? 'Update' : 'Submit'),
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
      ),
    );
  }
}

// ── Conversation Mission Sheet ──────────────────────────────────────────────

class _ConversationMissionSheet extends StatefulWidget {
  final Map<String, dynamic> quest;
  const _ConversationMissionSheet({required this.quest});

  @override
  State<_ConversationMissionSheet> createState() =>
      _ConversationMissionSheetState();
}

class _ConversationMissionSheetState
    extends State<_ConversationMissionSheet> {
  late Future<List<Map<String, dynamic>>> _sessionsFuture;
  String? _attachingId;
  Map<String, dynamic>? _lastResult;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = _loadSessions();
  }

  Future<List<Map<String, dynamic>>> _loadSessions() async {
    final uid = AuthService.instance.currentUser?.id ?? '';
    if (uid.isEmpty) return [];
    return SessionsService.instance.fetchRecentSessions(
      uid, limit: 25, completedOnly: true,
    );
  }

  Future<void> _attach(Map<String, dynamic> session) async {
    final sid = session['id'] as String?;
    if (sid == null) return;
    setState(() {
      _attachingId = sid;
      _lastResult = null;
    });
    final gp = context.read<GamificationProvider>();
    final ok = await gp.attachQuestSession(
      userQuestId: widget.quest['id'] as String,
      sessionId: sid,
    );
    if (!mounted) return;

    final updatedQuest = gp.dailyQuests.firstWhere(
      (q) => q['id'] == widget.quest['id'],
      orElse: () => widget.quest,
    );
    final state =
        (updatedQuest['brief_state'] as Map<String, dynamic>?) ?? {};

    setState(() {
      _attachingId = null;
      _lastResult = state;
    });

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not attach session.')),
      );
      return;
    }

    final passed = state['passed'] == true;
    final score = (state['score'] as num?)?.toDouble() ?? 0.0;
    if (passed) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mission complete! Score ${score.toStringAsFixed(1)}/10')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Session didn\'t meet the brief (score ${score.toStringAsFixed(1)}/10). Try another.',
          ),
        ),
      );
    }
  }

  String _formatRelative(String? createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final brief = widget.quest['brief'] as Map<String, dynamic>? ?? {};
    final topic = brief['topic'] as String?;
    final persona = brief['persona'] as String?;
    final minTurns = brief['min_turns'];
    final criteria = brief['completion_criteria'] as String?;

    final briefState = widget.quest['brief_state'] as Map<String, dynamic>? ?? {};
    final personalized = briefState['personalized_brief'] as Map<String, dynamic>?;
    final pScenario = personalized?['scenario'] as String?;
    final pContext = personalized?['context'] as String?;
    final pCriteria = (personalized?['criteria'] as List?)?.map((e) => e.toString()).toList();
    final pHint = personalized?['success_hint'] as String?;
    final title = widget.quest['title'] as String? ?? 'Conversation Mission';

    final feedback = _lastResult?['feedback'] as String?;
    final lastScore = (_lastResult?['score'] as num?)?.toDouble();
    final lastPassed = _lastResult?['passed'] == true;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtl) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A24) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.forum_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.manrope(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                controller: scrollCtl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.glassWhite : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: isDark
                            ? AppColors.glassBorder
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mission brief',
                            style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.primary)),
                        const SizedBox(height: 8),
                        if (personalized != null) ...[
                          if (pScenario != null)
                            _BriefRow(label: 'Scenario', value: pScenario),
                          if (pContext != null)
                            _BriefRow(label: 'Context', value: pContext),
                          if (pCriteria != null && pCriteria.isNotEmpty)
                            _BriefRow(label: 'Goal', value: pCriteria.join(' • ')),
                          if (minTurns != null)
                            _BriefRow(label: 'Min turns', value: minTurns.toString()),
                          if (pHint != null)
                            _BriefRow(label: 'Tip', value: pHint),
                        ] else ...[
                          if (topic != null) _BriefRow(label: 'Topic', value: topic),
                          if (persona != null)
                            _BriefRow(label: 'Persona', value: persona),
                          if (minTurns != null)
                            _BriefRow(label: 'Min turns', value: minTurns.toString()),
                          if (criteria != null)
                            _BriefRow(label: 'Goal', value: criteria),
                        ],
                      ],
                    ),
                  ),
                  if (feedback != null && feedback.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (lastPassed
                                ? AppColors.success
                                : AppColors.warning)
                            .withAlpha(isDark ? 30 : 18),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(
                          color: (lastPassed
                                  ? AppColors.success
                                  : AppColors.warning)
                              .withAlpha(80),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            lastPassed
                                ? Icons.verified_rounded
                                : Icons.info_rounded,
                            color: lastPassed
                                ? AppColors.success
                                : AppColors.warning,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (lastScore != null)
                                  Text(
                                    'Score: ${lastScore.toStringAsFixed(1)}/10',
                                    style: GoogleFonts.manrope(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                Text(
                                  feedback,
                                  style: GoogleFonts.manrope(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text('Pick a completed session to evaluate',
                      style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.slate300
                              : AppColors.slate700)),
                  const SizedBox(height: 10),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _sessionsFuture,
                    builder: (_, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snap.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Failed to load sessions: ${snap.error}',
                            style: GoogleFonts.manrope(fontSize: 13),
                          ),
                        );
                      }
                      final sessions = snap.data ?? [];
                      if (sessions.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No completed sessions yet. Hold a conversation matching this brief, then return here to evaluate it.',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              color: isDark
                                  ? AppColors.slate400
                                  : AppColors.slate600,
                            ),
                          ),
                        );
                      }
                      return Column(
                        children: [
                          for (final s in sessions)
                            _SessionPickRow(
                              session: s,
                              isAttaching: _attachingId == s['id'],
                              isDark: isDark,
                              onTap: _attachingId == null
                                  ? () => _attach(s)
                                  : null,
                              relative: _formatRelative(s['created_at'] as String?),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionPickRow extends StatelessWidget {
  final Map<String, dynamic> session;
  final bool isAttaching;
  final bool isDark;
  final VoidCallback? onTap;
  final String relative;

  const _SessionPickRow({
    required this.session,
    required this.isAttaching,
    required this.isDark,
    required this.onTap,
    required this.relative,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = (session['title'] as String?)?.trim();
    final summary = (session['summary'] as String?)?.trim();
    final mode = (session['mode'] as String?) ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.glassWhite : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.chat_bubble_rounded,
                    size: 16, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title?.isNotEmpty == true ? title! : 'Untitled session',
                      style: GoogleFonts.manrope(
                        fontSize: 14, fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (mode.isNotEmpty)
                          Text(
                            mode.replaceAll('_', ' '),
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        if (mode.isNotEmpty && relative.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text('•',
                              style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  color: AppColors.slate500)),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          relative,
                          style: GoogleFonts.manrope(
                              fontSize: 11, color: AppColors.slate500),
                        ),
                      ],
                    ),
                    if (summary != null && summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.slate400
                              : AppColors.slate600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              isAttaching
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.chevron_right_rounded,
                      color: AppColors.slate500),
            ],
          ),
        ),
      ),
    );
  }
}

class _BriefRow extends StatelessWidget {
  final String label;
  final String value;
  const _BriefRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: value),
          ],
        ),
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

// ── Reward Card ─────────────────────────────────────────────────────────────

class _RewardCard extends StatefulWidget {
  final Map<String, dynamic> reward;
  final int balance;
  final bool isDark;
  final Color primary;

  const _RewardCard({
    required this.reward,
    required this.balance,
    required this.isDark,
    required this.primary,
  });

  @override
  State<_RewardCard> createState() => _RewardCardState();
}

class _RewardCardState extends State<_RewardCard> {
  bool _busy = false;

  Future<void> _redeem() async {
    final id = widget.reward['id'] as String?;
    if (id == null) return;
    final cost = (widget.reward['cost_xp'] as num?)?.toInt() ?? 0;
    final title = widget.reward['title'] as String? ?? 'reward';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Redeem reward?'),
        content: Text('Spend $cost XP to unlock "$title"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final err = await context.read<GamificationProvider>().redeemReward(id);
    if (!mounted) return;
    setState(() => _busy = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err == null ? 'Unlocked "$title"!' : 'Failed: $err'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final reward = widget.reward;
    final cost = (reward['cost_xp'] as num?)?.toInt() ?? 0;
    final owned = reward['owned'] == true;
    final affordable = reward['affordable'] == true;
    final canRedeem = !owned && affordable && !_busy;
    final icon = reward['icon'] as String? ?? '🎁';
    final title = reward['title'] as String? ?? 'Reward';
    final desc = reward['description'] as String? ?? '';

    final accent = owned
        ? AppColors.success
        : (affordable ? widget.primary : AppColors.slate500);

    return SizedBox(
      width: 160,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.glassWhite : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(
            color: accent.withAlpha(owned ? 100 : 60),
            width: owned ? 1.5 : 1,
          ),
          boxShadow: owned
              ? [
                  BoxShadow(
                      color: AppColors.success.withAlpha(20),
                      blurRadius: 10),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(icon, style: const TextStyle(fontSize: 28)),
                if (owned)
                  Icon(Icons.check_circle,
                      color: AppColors.success, size: 18)
                else if (!affordable)
                  Icon(Icons.lock_rounded,
                      color: AppColors.slate500, size: 16),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 13, fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: Text(
                desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: isDark ? AppColors.slate400 : AppColors.slate600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: canRedeem ? _redeem : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  backgroundColor: owned
                      ? AppColors.success.withAlpha(40)
                      : (affordable
                          ? widget.primary.withAlpha(40)
                          : Colors.grey.withAlpha(30)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        owned
                            ? 'Owned'
                            : (affordable ? '$cost XP' : '$cost XP — locked'),
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Leaderboard Row ─────────────────────────────────────────────────────────

class _LeaderboardRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool isDark;
  final Color primary;

  const _LeaderboardRow({
    required this.row,
    required this.isDark,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final rank = (row['rank'] as num?)?.toInt() ?? 0;
    final name = row['display_name'] as String? ?? 'Anonymous';
    final score = (row['score'] as num?)?.toInt() ?? 0;
    final avatar = row['avatar_url'] as String?;
    final isYou = row['is_you'] == true;

    Color medalColor;
    IconData? medalIcon;
    if (rank == 1) {
      medalColor = const Color(0xFFFFD700);
      medalIcon = Icons.emoji_events_rounded;
    } else if (rank == 2) {
      medalColor = const Color(0xFFC0C0C0);
      medalIcon = Icons.emoji_events_rounded;
    } else if (rank == 3) {
      medalColor = const Color(0xFFCD7F32);
      medalIcon = Icons.emoji_events_rounded;
    } else {
      medalColor = isDark ? AppColors.slate400 : AppColors.slate500;
      medalIcon = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isYou ? primary.withAlpha(isDark ? 28 : 18) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: medalIcon != null
                ? Icon(medalIcon, color: medalColor, size: 20)
                : Text(
                    '#$rank',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: medalColor,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 16,
            backgroundColor: primary.withAlpha(40),
            backgroundImage: (avatar != null && avatar.isNotEmpty)
                ? NetworkImage(avatar)
                : null,
            child: (avatar == null || avatar.isEmpty)
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight:
                          isYou ? FontWeight.w800 : FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.slate900,
                    ),
                  ),
                ),
                if (isYou) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'YOU',
                      style: GoogleFonts.manrope(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '$score XP',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.xpGold,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Self Rank Pill ──────────────────────────────────────────────────────────

class _SelfRankPill extends StatelessWidget {
  final Map<String, dynamic> self;
  final bool isDark;

  const _SelfRankPill({required this.self, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final rank = self['rank'];
    final score = (self['score'] as num?)?.toInt() ?? 0;
    final optIn = self['leaderboard_opt_in'] as bool? ?? true;
    final theme = Theme.of(context);

    String label;
    if (!optIn) {
      label = 'Hidden — turn on visibility to compete';
    } else if (rank == null) {
      label = 'Earn XP to enter the board';
    } else {
      label = 'You are ranked #$rank with $score XP';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withAlpha(isDark ? 30 : 18),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: theme.colorScheme.primary.withAlpha(60),
          width: 0.6,
        ),
      ),
      child: Row(
        children: [
          Icon(
            optIn ? Icons.bar_chart_rounded : Icons.lock_outline_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Milestone Unlock Dialog ─────────────────────────────────────────────────

class _MilestoneDialog extends StatelessWidget {
  final Map<String, dynamic> badge;
  const _MilestoneDialog({required this.badge});

  Color _tierColor(String tier) {
    switch (tier) {
      case 'gold':
        return const Color(0xFFFFD700);
      case 'silver':
        return const Color(0xFFC0C0C0);
      default:
        return const Color(0xFFCD7F32);
    }
  }

  String _tierLabel(String tier) {
    switch (tier) {
      case 'gold':
        return 'Gold Milestone';
      case 'silver':
        return 'Silver Milestone';
      default:
        return 'Bronze Milestone';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final title = badge['title'] as String? ?? 'Milestone Unlocked';
    final description = badge['description'] as String? ?? '';
    final icon = badge['icon'] as String? ?? '🏆';
    final tier = badge['tier'] as String? ?? 'bronze';
    final xpReward = (badge['xp_reward'] as num?)?.toInt() ?? 0;
    final tierColor = _tierColor(tier);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xxl),
      ),
      backgroundColor: isDark ? const Color(0xFF1A1A24) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [tierColor.withAlpha(140), tierColor.withAlpha(30)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: tierColor.withAlpha(120),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Text(icon, style: const TextStyle(fontSize: 56)),
            ),
            const SizedBox(height: 18),
            Text(
              _tierLabel(tier).toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: tierColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 13.5,
                  color: isDark ? AppColors.slate300 : AppColors.slate600,
                ),
              ),
            ],
            if (xpReward > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.xpGold.withAlpha(40),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.xpGold.withAlpha(120), width: 0.8),
                ),
                child: Text(
                  '+$xpReward XP',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.xpGold,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: tierColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Awesome',
                  style: GoogleFonts.manrope(
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
