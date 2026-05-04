import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../theme/design_tokens.dart';
import '../services/auth_service.dart';
import '../services/connection_service.dart';
import '../services/voice_assistant_service.dart';
import '../providers/home_provider.dart';
import '../providers/gamification_provider.dart';
import '../providers/settings_provider.dart';
import '../repositories/graph_repository.dart';
import '../widgets/glass_morphism.dart';
import '../widgets/animated_background.dart';
import '../widgets/home/home_widgets.dart';
import '../widgets/insights/insight_item.dart';

import '../widgets/mood_check_widget.dart';
import '../widgets/performa_approval_sheet.dart';
import '../providers/performa_provider.dart';
import '../widgets/streak_strip.dart';
import '../widgets/skeleton_loader.dart';

// ============================================================================
//  HOME SCREEN
//  Data managed by HomeProvider; UI stays local.
// ============================================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _breatheCtrl;
  final ScrollController _homeScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _breatheCtrl = AnimationController(
      vsync: this,
      duration: AppDurations.breathe,
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HomeProvider>(context, listen: false).init();
      Provider.of<VoiceAssistantService>(context, listen: false).activate();
      Provider.of<GamificationProvider>(context, listen: false).init();
      
      final userId = AuthService.instance.currentUser?.id;
      if (userId != null) {
        Provider.of<GraphRepository>(context, listen: false).getGraphExport(userId, forceRefresh: true);
        Provider.of<PerformaProvider>(context, listen: false).load(userId).then((_) {
          if (mounted) PerformaApprovalSheet.showIfNeeded(context);
        });
      }
    });
  }

  @override
  void dispose() {
    _breatheCtrl.dispose();
    _homeScrollCtrl.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning,';
    if (hour < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }

  void _showNotificationsPanel(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final home = Provider.of<HomeProvider>(context, listen: false);
    home.clearUnread();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.35,
        builder: (_, scrollController) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0D1B1F).withAlpha(235) : Colors.white.withAlpha(242),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(
                  color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
                ),
              ),
              child: Column(
                children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Text(
                      'Notifications',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? Colors.white
                            : AppColors.slate900,
                      ),
                    ),
                    const Spacer(),
                    Selector<HomeProvider, bool>(
                      selector: (_, hp) =>
                          hp.highlights.isNotEmpty || hp.events.isNotEmpty,
                      builder: (context, hasItems, __) => hasItems
                          ? TextButton(
                              onPressed: () async {
                                await context
                                    .read<HomeProvider>()
                                    .clearAllHighlights();
                                if (context.mounted) Navigator.pop(ctx);
                              },
                              child: Text(
                                'Clear all',
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Selector<HomeProvider,
                    (List<Map<String, dynamic>>, List<Map<String, dynamic>>, List<Map<String, dynamic>>)>(
                  selector: (_, hp) =>
                      (hp.highlights, hp.events, hp.notifications),
                  shouldRebuild: (prev, next) =>
                      prev.$1.length != next.$1.length ||
                      prev.$2.length != next.$2.length ||
                      prev.$3.length != next.$3.length,
                  builder: (context, panelData, __) {
                    final (highlights, events, notifications) = panelData;
                    if (highlights.isEmpty && events.isEmpty && notifications.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_none_rounded,
                              size: 52,
                              color: isDark
                                  ? Colors.white24
                                  : Colors.grey.shade300,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No notifications yet',
                              style: GoogleFonts.manrope(
                                fontSize: 15,
                                color: isDark
                                    ? AppColors.slate500
                                    : Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Insights from your sessions will appear here.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.slate600
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        ...notifications.map(
                          (n) {
                            final type = n['notif_type'] as String? ?? 'info';
                            IconData icon = Icons.notifications;
                            Color c = AppColors.primary;
                            if (type == 'alert') { icon = Icons.warning_rounded; c = AppColors.error; }
                            else if (type == 'system') { icon = Icons.info_outline; c = Colors.blue; }

                            return NotificationCard(
                              isDark: isDark,
                              accentColor: c,
                              icon: icon,
                              title: n['title'] as String? ?? 'Notification',
                              body: n['body'] as String? ?? '',
                              badge: 'Update',
                              createdAt: n['created_at'] as String?,
                            );
                          }
                        ),
                        ...highlights.map(
                          (hl) => NotificationCard(
                            isDark: isDark,
                            accentColor: AppColors.error,
                            icon: Icons.warning_amber_rounded,
                            title: hl['title'] as String? ?? 'Highlight',
                            body: hl['body'] as String? ?? '',
                            badge:
                                hl['highlight_type'] as String? ?? 'Note',
                            createdAt: hl['created_at'] as String?,
                          ),
                        ),
                        ...events.map(
                          (ev) => NotificationCard(
                            isDark: isDark,
                            accentColor: AppColors.warning,
                            icon: Icons.event_rounded,
                            title: ev['title'] as String? ?? 'Event',
                            body: ev['description'] as String? ?? '',
                            badge: ev['due_text'] as String? ?? 'Event',
                            createdAt: ev['created_at'] as String?,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Selector<HomeProvider, bool>(
        selector: (_, home) => home.loading,
        builder: (context, isLoading, _) {
          if (isLoading) {
            return const Center(child: SkeletonCardGroup(count: 4));
          }
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! < -300) {
                Navigator.pushNamed(context, '/entities');
              }
            },
            child: Stack(
              children: [
                // Animated ambient background (replaces static mesh gradient)
                AnimatedAmbientBackground(
                  isDark: isDark,
                  scrollController: _homeScrollCtrl,
                ),
                SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        // --- FIXED HEADER ---
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              // Avatar with accent border
                              Selector<HomeProvider, String?>(
                                selector: (_, home) =>
                                    home.profile?['avatar_url'] as String? ??
                                    user?.userMetadata?['avatar_url'] as String?,
                                builder: (context, avatarUrl, _) => Semantics(
                                  label: 'Profile settings',
                                  button: true,
                                  child: GestureDetector(
                                    onTap: () => Navigator.pushNamed(
                                        context, '/settings'),
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Theme.of(context).colorScheme.primary,
                                          width: 2,
                                        ),
                                      ),
                                      child: ClipOval(
                                        child: avatarUrl != null
                                            ? CachedNetworkImage(
                                                imageUrl: avatarUrl,
                                                fit: BoxFit.cover,
                                                placeholder: (_, __) =>
                                                    Container(
                                                        color: AppColors
                                                            .surfaceDark),
                                              )
                                            : Container(
                                                color: isDark
                                                    ? AppColors.surfaceDark
                                                    : Colors.grey.shade200,
                                                child: Icon(
                                                  Icons.person,
                                                  color: isDark
                                                      ? Colors.white54
                                                      : Colors.grey,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Center(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Selector<GamificationProvider,
                                          (int, int, int, int, String)>(
                                        selector: (_, gp) => (
                                          gp.currentStreak,
                                          gp.totalXp,
                                          gp.level,
                                          gp.streakFreezes,
                                          gp.skillTierEmoji,
                                        ),
                                        builder: (context, gpData, __) {
                                          final (streak, totalXp, level,
                                              streakFreezes, skillTierEmoji) =
                                              gpData;
                                          return StreakStrip(
                                            streak: streak,
                                            totalXp: totalXp,
                                            level: level,
                                            streakFreezes: streakFreezes,
                                            skillTierEmoji: skillTierEmoji,
                                            onTap: () => Navigator.pushNamed(
                                                context, '/game-center'),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Selector<HomeProvider, (int, bool)>(
                                selector: (_, home) => (
                                  home.unreadNotifications,
                                  home.highlights.isNotEmpty,
                                ),
                                builder: (context, notifData, _) {
                                  final (unread, hasHighlights) = notifData;
                                  return Semantics(
                                    label: 'Notifications',
                                    button: true,
                                    child: GestureDetector(
                                      onTap: () =>
                                          _showNotificationsPanel(context),
                                      child: Stack(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Theme.of(context).colorScheme.primary,
                                                width: 2,
                                              ),
                                              color: isDark
                                                  ? AppColors.glassWhite
                                                  : Colors.grey.shade100,
                                            ),
                                            child: Icon(
                                              Icons.notifications_outlined,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                          if (unread > 0 || hasHighlights)
                                            Positioned(
                                              top: 0,
                                              right: 0,
                                              child: Container(
                                                width: unread > 9 ? 16 : 10,
                                                height: 10,
                                                decoration: BoxDecoration(
                                                  color: AppColors.error,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: isDark
                                                        ? AppColors.surfaceDark
                                                        : Colors.grey.shade100,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: unread > 0
                                                    ? Center(
                                                        child: Text(
                                                          '$unread',
                                                          style: const TextStyle(
                                                            fontSize: 6,
                                                            color: Colors.white,
                                                            fontWeight: FontWeight.w800,
                                                          ),
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        // --- SCROLLABLE CONTENT ---
                        Expanded(
                          child: CustomScrollView(
                            controller: _homeScrollCtrl,
                            slivers: [
                              // --- GREETING with streak ---
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      20, 12, 20, 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _getGreeting(),
                                              style: GoogleFonts.manrope(
                                                fontSize: 28,
                                                fontWeight: FontWeight.w800,
                                                color: isDark
                                                    ? Colors.white
                                                    : AppColors.slate900,
                                                height: 1.2,
                                              ),
                                            ),
                                          ),

                                        ],
                                      ),
                                      Selector<HomeProvider, String>(
                                        selector: (_, home) {
                                          final name = home.profile?['full_name'] as String? ??
                                              user?.userMetadata?['full_name'] as String? ??
                                              user?.userMetadata?['name'] as String? ??
                                              'Guest';
                                          return name.split(' ').first;
                                        },
                                        builder: (context, firstName, _) => ShaderMask(
                                          shaderCallback: (bounds) =>
                                              LinearGradient(
                                            colors: [
                                              Theme.of(context).colorScheme.primary,
                                              const Color(0xFF93C5FD),
                                            ],
                                          ).createShader(bounds),
                                          child: Text(
                                            '$firstName.',
                                            style: GoogleFonts.manrope(
                                              fontSize: 28,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                              height: 1.3,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // --- MOOD CHECK-IN ---
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                                  child: MoodCheckWidget(
                                    onMoodSelected: (mood) {
                                      // TODO: persist mood via provider
                                      debugPrint('Mood selected: $mood');
                                    },
                                  ),
                                ),
                              ),

                              // --- HERO CARD: LIVE WINGMAN ---
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 16, 16, 8),
                                  child: Selector<ConnectionService, bool>(
                                    selector: (_, cs) => cs.isConnected,
                                    builder: (context, isConnected, __) =>
                                        GestureDetector(
                                      onTap: () {
                                        HapticFeedback.mediumImpact();
                                        if (isConnected) {
                                          Navigator.pushNamed(
                                              context, '/new-session');
                                        } else {
                                          _showNotConnectedDialog(context);
                                        }
                                      },
                                      child: EntityOrb(
                                        isConnected: isConnected,
                                        breatheAnimation: _breatheCtrl,
                                        onTap: () {
                                          HapticFeedback.mediumImpact();
                                          if (isConnected) {
                                            Navigator.pushNamed(
                                                context, '/new-session');
                                          } else {
                                            _showNotConnectedDialog(context);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // --- QUICK ACTIONS ---
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Quick Actions',
                                        style: GoogleFonts.manrope(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          color: isDark ? Colors.white : AppColors.slate900,
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.edit_outlined, size: 18, color: isDark ? AppColors.slate400 : AppColors.slate500),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => _showQuickActionsEditSheet(context),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: Consumer<SettingsProvider>(
                                  builder: (context, sp, _) {
                                    return QuickActionsSection(
                                      style: sp.quickActionsStyle,
                                      enabledIds: sp.enabledQuickActions,
                                    );
                                  },
                                ),
                              ),

                              // --- RECENT INSIGHTS ---
                              SliverToBoxAdapter(
                                child: Selector<HomeProvider,
                                    (bool, List<Map<String, dynamic>>, List<Map<String, dynamic>>, List<Map<String, dynamic>>)>(
                                  selector: (_, home) => (
                                    home.insightsLoaded,
                                    home.events,
                                    home.highlights,
                                    home.notifications,
                                  ),
                                  shouldRebuild: (prev, next) =>
                                      prev.$1 != next.$1 ||
                                      prev.$2.length != next.$2.length ||
                                      prev.$3.length != next.$3.length ||
                                      prev.$4.length != next.$4.length,
                                  builder: (context, insightData, _) {
                                    final (insightsLoaded, events, highlights, notifications) = insightData;
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Header row
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Recent Insights',
                                                style: GoogleFonts.manrope(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w700,
                                                  color: isDark ? Colors.white : AppColors.slate900,
                                                ),
                                              ),
                                              Row(
                                                children: [
                                                  if (insightsLoaded &&
                                                      (events.isNotEmpty ||
                                                          highlights.isNotEmpty ||
                                                          notifications.isNotEmpty))
                                                    GestureDetector(
                                                      onTap: () => Navigator.pushNamed(context, '/insights'),
                                                      child: Text(
                                                        'See All',
                                                        style: GoogleFonts.manrope(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w700,
                                                          color: Theme.of(context).colorScheme.primary,
                                                        ),
                                                      ),
                                                    ),
                                                  const SizedBox(width: 8),
                                                  GestureDetector(
                                                    onTap: () => context.read<HomeProvider>().loadInsights(),
                                                    child: Icon(
                                                      Icons.refresh,
                                                      size: 18,
                                                      color: isDark ? AppColors.slate500 : Colors.grey.shade400,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Content
                                        if (!insightsLoaded)
                                          const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            child: SkeletonCardGroup(count: 3),
                                          )
                                        else if (events.isEmpty && highlights.isEmpty && notifications.isEmpty)
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                            child: HomeInsightCard(
                                              accentColor: Theme.of(context).colorScheme.primary,
                                              title: 'No insights yet',
                                              badge: 'Waiting',
                                              description:
                                                  'Start a Wingman session to generate personalized insights, events, and highlights.',
                                              isDark: isDark,
                                            ),
                                          )
                                        else
                                          RecentInsightsCarousel(
                                            events: events,
                                            highlights: highlights,
                                            notifications: notifications,
                                            homeScrollCtrl: _homeScrollCtrl,
                                            isDark: isDark,
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),

                              const SliverToBoxAdapter(child: SizedBox(height: 30)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

  void _showNotConnectedDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => GlassDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.error.withAlpha(26),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Not Connected',
                          style: GoogleFonts.manrope(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.slate900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Looks like you\'re not connected right now. Connect to start a new session.',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.slate400 : AppColors.slate500,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.slate400 : AppColors.slate500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.pushNamed(context, '/connections');
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(38),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                        ),
                        child: Text(
                          'Connect',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  void _showQuickActionsEditSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allActions = [
      {'id': 'consultant', 'title': 'Consultant AI', 'icon': Icons.psychology_rounded},
      {'id': 'sessions', 'title': 'History', 'icon': Icons.history_rounded},
      {'id': 'roleplay', 'title': 'Roleplay Mode', 'icon': Icons.theater_comedy_outlined},
      {'id': 'game-center', 'title': 'Game Center', 'icon': Icons.emoji_events},
      {'id': 'graph-explorer', 'title': 'Knowledge Graph', 'icon': Icons.hub_rounded},
      {'id': 'insights', 'title': 'Insights', 'icon': Icons.lightbulb_outline},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final sp = context.read<SettingsProvider>();
            final enabled = List<String>.from(sp.enabledQuickActions);

            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Customize Quick Actions',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...allActions.map((action) {
                      final isSelected = enabled.contains(action['id'] as String);
                      return CheckboxListTile(
                        title: Text(action['title'] as String, style: GoogleFonts.manrope()),
                        secondary: Icon(action['icon'] as IconData),
                        value: isSelected,
                        activeColor: Theme.of(context).colorScheme.primary,
                        onChanged: (val) {
                          if (val == true) {
                            enabled.add(action['id'] as String);
                          } else {
                            enabled.remove(action['id'] as String);
                          }
                          setSheetState(() {});
                          sp.setEnabledQuickActions(enabled);
                        },
                      );
                    }),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text('Done', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================================
//  RECENT INSIGHTS CAROUSEL
// ============================================================================
class RecentInsightsCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> highlights;
  final List<Map<String, dynamic>> notifications;
  final ScrollController homeScrollCtrl;
  final bool isDark;

  const RecentInsightsCarousel({
    super.key,
    required this.events,
    required this.highlights,
    required this.notifications,
    required this.homeScrollCtrl,
    required this.isDark,
  });

  @override
  State<RecentInsightsCarousel> createState() => _RecentInsightsCarouselState();
}

class _RecentInsightsCarouselState extends State<RecentInsightsCarousel> {
  late PageController _pageCtrl;
  String? _expandedId;
  double _previousScrollOffset = 0.0;
  int _currentPage = 0;
  final Map<int, double> _heights = {};

  List<Map<String, dynamic>> get _combinedInsights {
    final list = <Map<String, dynamic>>[];
    for (var e in widget.events) {
      list.add({'data': e, 'type': 'event', 'id': e['id']?.toString() ?? ''});
    }
    for (var h in widget.highlights) {
      list.add({'data': h, 'type': 'highlight', 'id': h['id']?.toString() ?? ''});
    }
    for (var n in widget.notifications) {
      list.add({'data': n, 'type': 'notification', 'id': n['id']?.toString() ?? ''});
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    final len = _combinedInsights.length;
    final initialPage = len > 1 ? len * 1000 : 0;
    _currentPage = initialPage;
    _pageCtrl = PageController(initialPage: initialPage, viewportFraction: 1.0);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _handleToggle(String id, bool isExpanded) {
    if (isExpanded) {
      setState(() {
        _expandedId = id;
      });
      _previousScrollOffset = widget.homeScrollCtrl.offset;
      Future.delayed(const Duration(milliseconds: 100), () {
        if (widget.homeScrollCtrl.hasClients) {
          widget.homeScrollCtrl.animateTo(
            widget.homeScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      });
    } else {
      setState(() {
        _expandedId = null;
      });
      if (widget.homeScrollCtrl.hasClients) {
        widget.homeScrollCtrl.animateTo(
          _previousScrollOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _dismissInsight(String id, String type) {
    context.read<HomeProvider>().dismissInsight(id, type);
    if (_expandedId == id) {
      setState(() {
        _expandedId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final combined = _combinedInsights;
    final len = combined.length;
    if (len == 0) return const SizedBox.shrink();

    final double carouselHeight = _heights[_currentPage] ?? 160.0;

    if (len == 1) {
      final item = combined.first;
      return SizedBox(
        height: carouselHeight,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.topCenter,
              child: OverflowBox(
                alignment: Alignment.topCenter,
                maxHeight: double.infinity,
                child: MeasureSize(
                  onChange: (size) {
                    if (mounted && _heights[0] != size.height) {
                      setState(() => _heights[0] = size.height);
                    }
                  },
                  child: _buildCard(item),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: carouselHeight,
      child: PageView.builder(
        controller: _pageCtrl,
        onPageChanged: (idx) {
          setState(() {
            _currentPage = idx;
          });
        },
        itemBuilder: (context, index) {
          final item = combined[index % len];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.topCenter,
              child: OverflowBox(
                alignment: Alignment.topCenter,
                maxHeight: double.infinity,
                child: MeasureSize(
                  onChange: (size) {
                    if (mounted && _heights[index] != size.height) {
                      setState(() => _heights[index] = size.height);
                    }
                  },
                  child: _buildCard(item),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> item) {
    final type = item['type'] as String;
    final data = item['data'] as Map<String, dynamic>;
    final id = item['id'] as String;

    Color accentColor;
    String title;
    String badge;
    String description;
    IconData icon;
    String? sessionId = data['session_id'] as String?;

    if (type == 'event') {
      accentColor = AppColors.warning;
      title = data['title'] as String? ?? 'Event';
      badge = data['due_text'] as String? ?? 'Event';
      description = data['description'] as String? ?? '';
      icon = Icons.event_rounded;
    } else if (type == 'highlight') {
      final hlType = (data['highlight_type'] as String? ?? '').toLowerCase();
      accentColor = InsightItem.colorForType(hlType);
      title = data['title'] as String? ?? 'Highlight';
      badge = InsightItem.badgeForType(hlType);
      description = data['body'] as String? ?? '';
      icon = InsightItem.iconForType(hlType);
    } else {
      accentColor = Theme.of(context).colorScheme.primary;
      title = data['title'] as String? ?? 'Notification';
      badge = 'Update';
      description = data['body'] as String? ?? '';
      icon = Icons.notifications_active_outlined;
    }

    return HomeInsightCard(
      key: ValueKey(id),
      accentColor: accentColor,
      title: title,
      badge: badge,
      description: description,
      isDark: widget.isDark,
      icon: icon,
      sessionId: sessionId,
      onToggle: (isExpanded) => _handleToggle(id, isExpanded),
      onLongPress: () => _dismissInsight(id, type),
    );
  }
}

// ============================================================================
//  MEASURE SIZE UTILITY
// ============================================================================
class MeasureSize extends SingleChildRenderObjectWidget {
  final void Function(Size size) onChange;

  const MeasureSize({
    super.key,
    required this.onChange,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _MeasureSizeRenderObject(onChange);
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  Size? oldSize;
  final void Function(Size size) onChange;

  _MeasureSizeRenderObject(this.onChange);

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size;
    if (newSize != null && oldSize != newSize) {
      oldSize = newSize;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChange(newSize);
      });
    }
  }
}
