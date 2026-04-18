import 'dart:async';
import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/design_tokens.dart';
import '../services/app_cache_service.dart';
import '../services/auth_service.dart';
import '../services/connection_service.dart';
import '../services/voice_assistant_service.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../routes/app_routes.dart';
import '../widgets/settings/settings_widgets.dart';
import '../widgets/settings/settings_dialogs.dart';
import '../widgets/animated_background.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoggingOut = false;
  bool _notificationsGranted = false;

  @override
  void initState() {
    super.initState();
    _checkNotificationPermission();
  }

  Future<void> _checkNotificationPermission() async {
    final status = await Permission.notification.status;
    if (mounted) setState(() => _notificationsGranted = status.isGranted);
  }

  Future<void> _toggleNotifications(bool _) async {
    if (_notificationsGranted) {
      await openAppSettings();
    } else {
      final status = await Permission.notification.request();
      if (mounted) setState(() => _notificationsGranted = status.isGranted);
    }
  }

  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);
    try {
      context.read<AppCacheService>().invalidateAll();
      await AuthService.instance.signOut();
      if (mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (Route<dynamic> route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null &&
            details.primaryVelocity! < -300) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: Stack(
          children: [
            // Animated ambient background
            Positioned.fill(
              child: AnimatedAmbientBackground(isDark: isDark),
            ),

            SafeArea(
              child: CustomScrollView(
                slivers: [
                  // ── Header ────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            tooltip: 'Go back',
                            icon: Icon(
                              Icons.arrow_back,
                              size: 26,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Settings',
                            style: GoogleFonts.manrope(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.slate900,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Done',
                              style: GoogleFonts.manrope(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Profile Hero Card ─────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _ProfileHeroCard(isDark: isDark, cs: cs),
                    ),
                  ),

                  // ── Content ───────────────────────────────────────────
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 24),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // PREFERENCES
                        _SectionHeader(
                          label: 'Preferences',
                          icon: Icons.tune_rounded,
                          color: const Color(0xFF38BDF8),
                        ),
                        const SizedBox(height: 8),
                        GroupedContainer(
                          isDark: isDark,
                          children: [
                            Consumer<ThemeProvider>(
                              builder: (context, themeProvider, _) =>
                                  SettingsTile(
                                isDark: isDark,
                                iconBg:
                                    const Color(0xFF38BDF8).withAlpha(51),
                                iconColor: const Color(0xFF38BDF8),
                                icon: Icons.brightness_medium_outlined,
                                title: 'Theme Mode',
                                trailing: Text(
                                  themeProvider.themeMode == ThemeMode.system
                                      ? 'System'
                                      : themeProvider.themeMode ==
                                              ThemeMode.dark
                                          ? 'Dark'
                                          : 'Light',
                                  style: GoogleFonts.manrope(
                                      fontSize: 13,
                                      color: AppColors.textMuted),
                                ),
                                onTap: () => _showThemeModePicker(
                                    context, themeProvider),
                              ),
                            ),
                            TileDivider(isDark: isDark),
                            Consumer<ThemeProvider>(
                              builder: (context, themeProvider, _) =>
                                  SettingsTile(
                                isDark: isDark,
                                iconBg: themeProvider.seedColor.withAlpha(51),
                                iconColor: themeProvider.seedColor,
                                icon: Icons.color_lens_outlined,
                                title: 'Accent Color',
                                trailing: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: themeProvider.seedColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                onTap: () =>
                                    _showColorPicker(context, themeProvider),
                              ),
                            ),
                            TileDivider(isDark: isDark),
                            SettingsTile(
                              isDark: isDark,
                              iconBg: const Color(0xFF34D399).withAlpha(51),
                              iconColor: const Color(0xFF34D399),
                              icon: Icons.translate,
                              title: 'Language',
                              trailing: Text(
                                'English (US)',
                                style: GoogleFonts.manrope(
                                    fontSize: 13, color: AppColors.textMuted),
                              ),
                              onTap: () => Navigator.pushNamed(
                                  context, AppRoutes.language),
                            ),
                            TileDivider(isDark: isDark),
                            Consumer<SettingsProvider>(
                              builder: (context, settingsProvider, _) =>
                                  SettingsTile(
                                isDark: isDark,
                                iconBg: const Color(0xFFF59E0B).withAlpha(51),
                                iconColor: const Color(0xFFF59E0B),
                                icon: Icons.grid_view_rounded,
                                title: 'Quick Actions Layout',
                                trailing: Text(
                                  settingsProvider.quickActionsStyle == 'list'
                                      ? 'List'
                                      : settingsProvider.quickActionsStyle == 'icons'
                                          ? 'Icons'
                                          : 'Grid',
                                  style: GoogleFonts.manrope(
                                      fontSize: 13, color: AppColors.textMuted),
                                ),
                                onTap: () => _showQuickActionsStylePicker(
                                    context, settingsProvider),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // ASSISTANT
                        _SectionHeader(
                          label: 'Assistant',
                          icon: Icons.chat_bubble_outline_rounded,
                          color: const Color(0xFFFB7185),
                        ),
                        const SizedBox(height: 8),
                        Consumer<SettingsProvider>(
                          builder: (context, settingsProvider, _) =>
                              GroupedContainer(
                            isDark: isDark,
                            children: [
                              SettingsTile(
                                isDark: isDark,
                                iconBg:
                                    const Color(0xFFFB7185).withAlpha(51),
                                iconColor: const Color(0xFFFB7185),
                                icon: Icons.chat_bubble_outline,
                                title: 'Live Tone',
                                trailing: Text(
                                  settingsProvider.defaultLiveTone[0]
                                          .toUpperCase() +
                                      settingsProvider.defaultLiveTone
                                          .substring(1),
                                  style: GoogleFonts.manrope(
                                      fontSize: 13,
                                      color: AppColors.textMuted),
                                ),
                                onTap: () => _showLiveTonePicker(
                                    context, settingsProvider),
                              ),
                              TileDivider(isDark: isDark),
                              SettingsTile(
                                isDark: isDark,
                                iconBg:
                                    const Color(0xFF60A5FA).withAlpha(51),
                                iconColor: const Color(0xFF60A5FA),
                                icon: Icons.person_outline,
                                title: 'Consultant Tone',
                                trailing: Text(
                                  settingsProvider.defaultConsultantTone[0]
                                          .toUpperCase() +
                                      settingsProvider.defaultConsultantTone
                                          .substring(1),
                                  style: GoogleFonts.manrope(
                                      fontSize: 13,
                                      color: AppColors.textMuted),
                                ),
                                onTap: () => _showConsultantTonePicker(
                                    context, settingsProvider),
                              ),
                              TileDivider(isDark: isDark),
                              ToggleTile(
                                isDark: isDark,
                                iconBg: const Color(0xFFF59E0B).withAlpha(51),
                                iconColor: const Color(0xFFF59E0B),
                                icon: Icons.question_answer_outlined,
                                title: 'Always ask for tone when starting',
                                value: settingsProvider.alwaysPromptForTone,
                                onChanged: (val) =>
                                    settingsProvider.setAlwaysPromptForTone(
                                        val),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // VOICE ASSISTANT
                        _SectionHeader(
                          label: 'Voice Assistant',
                          icon: Icons.mic_rounded,
                          color: cs.primary,
                        ),
                        const SizedBox(height: 8),
                        Consumer<VoiceAssistantService>(
                          builder: (context, voice, _) => GroupedContainer(
                            isDark: isDark,
                            children: [
                              ToggleTile(
                                isDark: isDark,
                                iconBg: cs.primary.withAlpha(51),
                                iconColor: cs.primary,
                                icon: Icons.hearing_rounded,
                                title: '"Hey Bubbles" Wake Word',
                                value: voice.isWakeWordEnabled,
                                onChanged: (val) =>
                                    voice.setWakeWordEnabled(val),
                              ),
                              TileDivider(isDark: isDark),
                              SettingsTile(
                                isDark: isDark,
                                iconBg: Colors.teal.withAlpha(51),
                                iconColor: cs.primary,
                                icon: Icons.record_voice_over_outlined,
                                title: 'Voice Mode',
                                trailing: Text(
                                  voice.voiceMode.name[0].toUpperCase() +
                                      voice.voiceMode.name.substring(1),
                                  style: GoogleFonts.manrope(
                                      fontSize: 13,
                                      color: AppColors.textMuted),
                                ),
                                onTap: () =>
                                    _showVoiceModePicker(context, voice),
                              ),
                              TileDivider(isDark: isDark),
                              VoiceEnrollmentSection(isDark: isDark),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // NOTIFICATIONS
                        _SectionHeader(
                          label: 'Notifications',
                          icon: Icons.notifications_outlined,
                          color: const Color(0xFFF43F5E),
                        ),
                        const SizedBox(height: 8),
                        Consumer<ConnectionService>(
                          builder: (context, conn, _) => GroupedContainer(
                            isDark: isDark,
                            children: [
                              ToggleTile(
                                isDark: isDark,
                                iconBg:
                                    const Color(0xFFF43F5E).withAlpha(51),
                                iconColor: const Color(0xFFF43F5E),
                                icon: Icons.notifications_outlined,
                                title: 'Push Notifications',
                                value: _notificationsGranted,
                                onChanged: _toggleNotifications,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // PRIVACY & DATA
                        _SectionHeader(
                          label: 'Privacy & Data',
                          icon: Icons.shield_outlined,
                          color: AppColors.slate400,
                        ),
                        const SizedBox(height: 8),
                        GroupedContainer(
                          isDark: isDark,
                          children: [
                            SettingsTile(
                              isDark: isDark,
                              iconBg: Colors.grey.withAlpha(51),
                              iconColor: isDark
                                  ? AppColors.slate300
                                  : Colors.grey.shade600,
                              icon: Icons.storage_outlined,
                              title: 'Data Management',
                              onTap: () => Navigator.pushNamed(
                                  context, AppRoutes.data),
                            ),
                            TileDivider(isDark: isDark),
                            SettingsTile(
                              isDark: isDark,
                              iconBg: Colors.grey.withAlpha(51),
                              iconColor: isDark
                                  ? AppColors.slate300
                                  : Colors.grey.shade600,
                              icon: Icons.lock_outline,
                              title: 'Permissions',
                              onTap: () => Navigator.pushNamed(
                                  context, AppRoutes.permissions),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // ABOUT & SUPPORT
                        _SectionHeader(
                          label: 'About & Support',
                          icon: Icons.info_outline_rounded,
                          color: const Color(0xFF10B981),
                        ),
                        const SizedBox(height: 8),
                        GroupedContainer(
                          isDark: isDark,
                          children: [
                            SettingsTile(
                              isDark: isDark,
                              iconBg: cs.primary.withAlpha(38),
                              iconColor: cs.primary,
                              icon: Icons.info_outline_rounded,
                              title: 'About Bubbles',
                              onTap: () =>
                                  Navigator.pushNamed(context, '/about'),
                            ),
                            TileDivider(isDark: isDark),
                            SettingsTile(
                              isDark: isDark,
                              iconBg:
                                  const Color(0xFF10B981).withAlpha(38),
                              iconColor: const Color(0xFF10B981),
                              icon: Icons.mail_outline_rounded,
                              title: 'Contact Us',
                              onTap: () =>
                                  showContactSheet(context, isDark),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // LOGOUT BUTTON
                        _isLoggingOut
                            ? const Center(child: CircularProgressIndicator())
                            : _LogoutButton(onTap: _logout),

                        const SizedBox(height: 24),

                        // VERSION FOOTER
                        Center(
                          child: Column(
                            children: [
                              Text(
                                'Bubbles v1.0.4',
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.slate600
                                      : AppColors.slate400,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Made with AI Love',
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  color: isDark
                                      ? AppColors.slate700
                                      : AppColors.slate300,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showThemeModePicker(BuildContext context, ThemeProvider themeProvider) =>
      showThemeModePicker(context, themeProvider);

  void _showColorPicker(BuildContext context, ThemeProvider themeProvider) =>
      showColorPicker(context, themeProvider);

  void _showVoiceModePicker(BuildContext context, VoiceAssistantService voice) =>
      showVoiceModePicker(context, voice);

  void _showLiveTonePicker(BuildContext context, SettingsProvider p) =>
      showLiveTonePicker(context, p);

  void _showConsultantTonePicker(BuildContext context, SettingsProvider p) =>
      showConsultantTonePicker(context, p);

  void _showQuickActionsStylePicker(BuildContext context, SettingsProvider p) =>
      showQuickActionsStylePicker(context, p);
}

// ── Profile Hero Card ──────────────────────────────────────────────────────────

class _ProfileHeroCard extends StatelessWidget {
  final bool isDark;
  final ColorScheme cs;
  const _ProfileHeroCard({required this.isDark, required this.cs});

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final name = user?.userMetadata?['full_name'] as String? ??
        user?.email?.split('@').first ??
        'Guest';
    final email = user?.email ?? '';
    final avatarUrl =
        user?.userMetadata?['avatar_url'] as String?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.glassWhite : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(
          color: isDark
              ? AppColors.glassBorder
              : Colors.grey.shade200,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cs.primary.withAlpha(80), width: 2),
              gradient: avatarUrl == null
                  ? LinearGradient(
                      colors: [cs.primary, cs.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              image: avatarUrl != null
                  ? DecorationImage(
                      image: NetworkImage(avatarUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: avatarUrl == null
                ? Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'B',
                      style: GoogleFonts.manrope(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  )
                : null,
          ),

          const SizedBox(width: 16),

          // Name + email
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.manrope(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // Plan badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(28),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: cs.primary.withAlpha(60)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.diamond_outlined,
                          size: 11, color: cs.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Free Plan',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Edit / Subscription chevron
          IconButton(
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.subscription),
            icon: Icon(
              Icons.chevron_right_rounded,
              color: isDark
                  ? AppColors.slate400
                  : AppColors.slate500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 0),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Logout Button ──────────────────────────────────────────────────────────────

class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LogoutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.error.withAlpha(isDark ? 40 : 20),
              AppColors.error.withAlpha(isDark ? 24 : 12),
            ],
          ),
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(
            color: AppColors.error.withAlpha(isDark ? 80 : 60),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded,
                size: 18, color: AppColors.error),
            const SizedBox(width: 8),
            Text(
              'Log Out',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
