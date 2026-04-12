import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../theme/design_tokens.dart';
import '../services/auth_service.dart';
import '../services/connection_service.dart';
import '../services/voice_assistant_service.dart';
import '../providers/home_provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/glass_morphism.dart';

// ============================================================================
//  HOME SCREEN
//  Data managed by HomeProvider; UI stays local.
// ============================================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HomeProvider>(context, listen: false).init();
      Provider.of<VoiceAssistantService>(context, listen: false).activate();
    });
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
                border: Border(
                  top: BorderSide(color: isDark ? AppColors.glassBorder : Colors.grey.shade200),
                  left: BorderSide(color: isDark ? AppColors.glassBorderLight : Colors.grey.shade100),
                  right: BorderSide(color: isDark ? AppColors.glassBorderLight : Colors.grey.shade100),
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
                    Consumer<HomeProvider>(
                      builder: (_, hp, __) =>
                          (hp.highlights.isNotEmpty || hp.events.isNotEmpty)
                              ? TextButton(
                                  onPressed: () async {
                                    await hp.clearAllHighlights();
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
                child: Consumer<HomeProvider>(
                  builder: (_, hp, __) {
                    if (hp.highlights.isEmpty && hp.events.isEmpty && hp.notifications.isEmpty) {
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
                        ...hp.notifications.map(
                          (n) {
                            final type = n['notif_type'] as String? ?? 'info';
                            IconData icon = Icons.notifications;
                            Color c = AppColors.primary;
                            if (type == 'alert') { icon = Icons.warning_rounded; c = AppColors.error; }
                            else if (type == 'system') { icon = Icons.info_outline; c = Colors.blue; }

                            return _NotificationCard(
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
                        ...hp.highlights.map(
                          (hl) => _NotificationCard(
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
                        ...hp.events.map(
                          (ev) => _NotificationCard(
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

    return Consumer<HomeProvider>(
      builder: (context, home, _) {
        final name = home.profile?['full_name'] ??
            user?.userMetadata?['full_name'] ??
            user?.userMetadata?['name'] ??
            'Guest';
        final firstName = name.toString().split(' ').first;
        final avatarUrl =
            home.profile?['avatar_url'] ?? user?.userMetadata?['avatar_url'];

        return Scaffold(
          backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
          body: home.loading
              ? const Center(child: CircularProgressIndicator())
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity != null) {
                      if (details.primaryVelocity! > 300) {
                        Navigator.pushNamed(context, '/settings');
                      } else if (details.primaryVelocity! < -300) {
                        Navigator.pushNamed(context, '/entities');
                      }
                    }
                  },
                  child: Stack(
                    children: [
                      // Mesh gradient
                      if (isDark) ...[
                        Positioned(
                          top: -120,
                          left: -120,
                          child: Container(
                            width: 400,
                            height: 400,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [Theme.of(context).colorScheme.primary.withAlpha(38), Colors.transparent],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -120,
                          right: -120,
                          child: Container(
                            width: 400,
                            height: 400,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [Theme.of(context).colorScheme.primary.withAlpha(26), Colors.transparent],
                              ),
                            ),
                          ),
                        ),
                      ],
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
                              Builder(
                                builder: (context) => Semantics(
                                  label: 'Profile settings',
                                  button: true,
                                  child: GestureDetector(
                                    onTap: () => Navigator.pushNamed(
                                        context, '/settings'),
                                    child: Container(
                                      width: 44,
                                      height: 44,
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
                              Text(
                                'Bubbles',
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.slate900,
                                ),
                              ),
                              Semantics(
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
                                          color: isDark
                                              ? AppColors.glassWhite
                                              : Colors.grey.shade100,
                                        ),
                                        child: Icon(
                                          Icons.notifications_outlined,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.grey.shade700,
                                        ),
                                      ),
                                      if (home.unreadNotifications > 0 ||
                                          home.highlights.isNotEmpty)
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: Container(
                                            width:
                                                home.unreadNotifications >
                                                        9
                                                    ? 16
                                                    : 10,
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
                                            child: home
                                                        .unreadNotifications >
                                                    0
                                                ? Center(
                                                    child: Text(
                                                      '${home.unreadNotifications}',
                                                      style:
                                                          const TextStyle(
                                                        fontSize: 6,
                                                        color:
                                                            Colors.white,
                                                        fontWeight:
                                                            FontWeight
                                                                .w800,
                                                      ),
                                                    ),
                                                  )
                                                : null,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // --- SCROLLABLE CONTENT ---
                        Expanded(
                          child: CustomScrollView(
                            slivers: [
                              // --- GREETING ---
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      20, 12, 20, 16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
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
                                      ShaderMask(
                                        shaderCallback: (bounds) =>
                                            LinearGradient(
                                          colors: [
                                            Theme.of(context).colorScheme.primary,
                                            Color(0xFF93C5FD),
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
                                    ],
                                  ),
                                ),
                              ),

                              // --- HERO CARD: LIVE WINGMAN ---
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 16, 16, 8),
                                  child: Consumer<ConnectionService>(
                                    builder: (context,
                                        connectionService, child) {
                                      final isConnected =
                                          connectionService.isConnected;
                                      return GestureDetector(
                                        onTap: () {
                                          if (isConnected) {
                                            Navigator.pushNamed(
                                                context, '/new-session');
                                          } else {
                                            _showNotConnectedDialog(
                                                context);
                                          }
                                        },
                                        child: _buildHeroCard(
                                            context,
                                            isDark,
                                            isConnected),
                                      );
                                    },
                                  ),
                                ),
                              ),

                              // --- QUICK ACTIONS ---
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 12, 16, 4),
                                  child: Text(
                                    'Quick Actions',
                                    style: GoogleFonts.manrope(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white
                                          : AppColors.slate900,
                                    ),
                                  ),
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _QuickActionCard(
                                          icon: Icons.forum,
                                          iconColor:
                                              Theme.of(context).colorScheme.secondary,
                                          iconBg: Theme.of(context).colorScheme.secondary
                                              .withAlpha(51),
                                          title: 'Consultant AI',
                                          subtitle: 'Strategy & advice',
                                          onTap: () =>
                                              Navigator.pushNamed(
                                                  context,
                                                  '/consultant'),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _QuickActionCard(
                                          icon: Icons.auto_awesome,
                                          iconColor:
                                              const Color(0xFF34D399),
                                          iconBg: const Color(0xFF34D399)
                                              .withAlpha(51),
                                          title: 'History',
                                          subtitle: 'Past sessions',
                                          onTap: () =>
                                              Navigator.pushNamed(
                                                  context, '/sessions'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _QuickActionCard(
                                          icon: Icons.theater_comedy_outlined,
                                          iconColor: Colors.deepPurple,
                                          iconBg: Colors.deepPurple.withAlpha(51),
                                          title: 'Roleplay Mode',
                                          subtitle: 'Practice with personas',
                                          onTap: () =>
                                              Navigator.pushNamed(
                                                  context, '/roleplay-setup'),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _QuickActionCard(
                                          icon: Icons.emoji_events,
                                          iconColor: Colors.amber,
                                          iconBg: Colors.amber.withAlpha(51),
                                          title: 'Quests & XP',
                                          subtitle: 'Daily challenges',
                                          onTap: () =>
                                              Navigator.pushNamed(
                                                  context, '/quests'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // --- RECENT INSIGHTS ---
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 16, 16, 4),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Recent Insights',
                                        style: GoogleFonts.manrope(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : AppColors.slate900,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          if (home.insightsLoaded &&
                                              (home.events.isNotEmpty ||
                                                  home.highlights.isNotEmpty ||
                                                  home.notifications.isNotEmpty))
                                            GestureDetector(
                                              onTap: () => Navigator.pushNamed(
                                                  context, '/insights'),
                                              child: Text(
                                                'See All',
                                                style: GoogleFonts.manrope(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                ),
                                              ),
                                            ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: home.loadInsights,
                                            child: Icon(
                                              Icons.refresh,
                                              size: 18,
                                              color: isDark
                                                  ? AppColors.slate500
                                                  : Colors.grey.shade400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              if (!home.insightsLoaded)
                                const SliverToBoxAdapter(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    child: Center(
                                        child:
                                            CircularProgressIndicator(
                                                strokeWidth: 2)),
                                  ),
                                )
                              else if (home.events.isEmpty &&
                                  home.highlights.isEmpty &&
                                  home.notifications.isEmpty)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 8, 16, 8),
                                    child: _InsightCard(
                                      accentColor: Theme.of(context).colorScheme.primary,
                                      title: 'No insights yet',
                                      badge: 'Waiting',
                                      description:
                                          'Start a Wingman session to generate personalized insights, events, and highlights.',
                                      isDark: isDark,
                                    ),
                                  ),
                                )
                              else ...[
                                ...home.events.map(
                                  (ev) => SliverToBoxAdapter(
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.fromLTRB(
                                              16, 4, 16, 4),
                                      child: _InsightCard(
                                        accentColor:
                                            AppColors.warning,
                                        title: ev['title']
                                                as String? ??
                                            'Event',
                                        badge: ev['due_text']
                                                as String? ??
                                            'Event',
                                        description:
                                            ev['description']
                                                    as String? ??
                                                '',
                                        isDark: isDark,
                                        icon: Icons.event_rounded,
                                      ),
                                    ),
                                  ),
                                ),
                                ...home.highlights.map(
                                  (hl) {
                                    final hlType =
                                        (hl['highlight_type'] as String? ?? '')
                                            .toLowerCase();
                                    final hlColor = _highlightColor(
                                        hlType,
                                        Theme.of(context).colorScheme.primary);
                                    final hlIcon =
                                        _highlightIcon(hlType);
                                    return SliverToBoxAdapter(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 4, 16, 4),
                                        child: _InsightCard(
                                          accentColor: hlColor,
                                          title: hl['title'] as String? ??
                                              'Highlight',
                                          badge: _highlightBadge(hlType),
                                          description:
                                              hl['body'] as String? ?? '',
                                          isDark: isDark,
                                          icon: hlIcon,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                ...home.notifications.map(
                                  (tn) => SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                                      child: _InsightCard(
                                        accentColor: Theme.of(context).colorScheme.primary,
                                        title: tn['title'] as String? ?? 'Notification',
                                        badge: 'Update',
                                        description: tn['body'] as String? ?? '',
                                        isDark: isDark,
                                        icon: Icons.notifications_active_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 30)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                    ],
                  ),
                ),
        );
      },
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
                    'You are not connected to the server. Would you like to connect now?',
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

  Widget _buildHeroCard(
      BuildContext context, bool isDark, bool isConnected) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        color: isDark ? AppColors.glassWhite : Colors.white,
        border: Border.all(
          color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withAlpha(isDark ? 38 : 20),
            blurRadius: 24,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      label: isConnected
                          ? 'Server status: connected'
                          : 'Server status: disconnected',
                      child: Row(
                        children: [
                          if (isConnected)
                            _PulseDot()
                          else
                            const Icon(Icons.circle,
                                color: AppColors.error, size: 8),
                          const SizedBox(width: 8),
                          Text(
                            isConnected
                                ? 'STATUS: ACTIVE'
                                : 'STATUS: DISCONNECTED',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isConnected
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                  : AppColors.error,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Live Wingman',
                      style: GoogleFonts.manrope(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Colors.white
                            : AppColors.slate900,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.glassWhite
                        : Theme.of(context).colorScheme.primary.withAlpha(26),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Icon(
                    Icons.mic,
                    color: isDark
                        ? Colors.white
                        : Theme.of(context).colorScheme.primary,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Ready to listen. I\'ll provide real-time cues discreetly through your connected device.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppColors.slate300
                    : AppColors.slate600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withAlpha(200)],
                      ),
                      borderRadius:
                          BorderRadius.circular(AppRadius.full),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withAlpha(51),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.record_voice_over,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Start Session',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () =>
                      Navigator.pushNamed(context, '/settings'),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.glassWhite
                          : Colors.black.withAlpha(10),
                      borderRadius:
                          BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                        color: isDark
                            ? AppColors.glassBorder
                            : Colors.black.withAlpha(20),
                      ),
                    ),
                    child: Icon(
                      Icons.settings,
                      color: isDark
                          ? Colors.white
                          : AppColors.slate600,
                      size: 20,
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
}

// --- WIDGETS ---

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.7, end: 0.0).animate(_controller),
            child: ScaleTransition(
              scale: Tween(begin: 1.0, end: 2.0).animate(_controller),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.glassWhite : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(
            color: isDark
                ? AppColors.glassBorder
                : Colors.grey.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? Colors.white
                    : AppColors.slate900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: isDark
                    ? AppColors.slate400
                    : AppColors.slate500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Highlight type helpers --------------------------------------------------

Color _highlightColor(String type, Color fallback) {
  switch (type) {
    case 'key_fact':    return const Color(0xFF6366F1); // indigo
    case 'action_item': return const Color(0xFF10B981); // emerald
    case 'risk':        return const Color(0xFFEF4444); // red
    case 'opportunity': return const Color(0xFFF59E0B); // amber
    case 'conflict':    return const Color(0xFFEC4899); // pink
    default:            return fallback;
  }
}

IconData _highlightIcon(String type) {
  switch (type) {
    case 'key_fact':    return Icons.lightbulb_outline_rounded;
    case 'action_item': return Icons.check_circle_outline_rounded;
    case 'risk':        return Icons.warning_amber_rounded;
    case 'opportunity': return Icons.trending_up_rounded;
    case 'conflict':    return Icons.report_gmailerrorred_outlined;
    default:            return Icons.bookmark_outline_rounded;
  }
}

String _highlightBadge(String type) {
  switch (type) {
    case 'key_fact':    return 'Key Fact';
    case 'action_item': return 'Action Item';
    case 'risk':        return 'Risk';
    case 'opportunity': return 'Opportunity';
    case 'conflict':    return 'Conflict';
    default:
      return type.isEmpty
          ? 'Note'
          : type[0].toUpperCase() + type.substring(1).replaceAll('_', ' ');
  }
}

// ---------------------------------------------------------------------------

class _InsightCard extends StatelessWidget {
  final Color accentColor;
  final String title;
  final String badge;
  final String description;
  final bool isDark;
  final IconData? icon;

  const _InsightCard({
    required this.accentColor,
    required this.title,
    required this.badge,
    required this.description,
    required this.isDark,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.glassWhite : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border:
            Border(left: BorderSide(color: accentColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: accentColor),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? Colors.white
                          : AppColors.slate900,
                    ),
                  ),
                ],
              ),
              Text(
                badge,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: isDark
                  ? AppColors.slate400
                  : AppColors.slate500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final Color accentColor;
  final IconData icon;
  final String title;
  final String body;
  final String badge;
  final String? createdAt;
  final bool isDark;

  const _NotificationCard({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.body,
    required this.badge,
    required this.isDark,
    this.createdAt,
  });

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.glassWhite : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border:
            Border(left: BorderSide(color: accentColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Colors.white
                        : AppColors.slate900,
                  ),
                ),
              ),
              Text(
                _formatTime(createdAt),
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.slate500
                      : Colors.grey.shade400,
                ),
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: isDark
                    ? AppColors.slate400
                    : AppColors.slate500,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accentColor.withAlpha(31),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
