// Purpose: Settings hub screen — top-level settings menu that links to all sub-settings screens.
﻿import 'dart:async';
import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/help_content.dart';
import '../theme/design_tokens.dart';
import '../services/app_cache_service.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../routes/app_routes.dart';
import '../widgets/app_sheet.dart';
import '../widgets/settings/settings_widgets.dart';
import '../widgets/animated_background.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/help_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoggingOut = false;

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
        AppSnackBar.error(context, 'Logout failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: Stack(
          children: [
            // Animated ambient background
            Positioned.fill(
              child: AnimatedAmbientBackground(isDark: isDark),
            ),

            SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                child: Column(
                  children: [
                    // Header
                    Padding(
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
                          Flexible(
                            child: Text(
                              'Settings',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.slate900,
                              ),
                            ),
                          ),
                          const Spacer(),
                          const HelpIconButton(screen: HelpScreen.settings),
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

                    const SizedBox(height: 16),

                    // Profile Hero Card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ProfileHeroCard(isDark: isDark, cs: cs),
                    ),

                    const SizedBox(height: 24),

                    // Content
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GroupedContainer(
                        isDark: isDark,
                        children: [
                          SettingsNavigationTile(
                            isDark: isDark,
                            iconBg: const Color(0xFF8B5CF6).withAlpha(51),
                            iconColor: const Color(0xFF8B5CF6),
                            icon: Icons.badge_outlined,
                            title: 'Performa',
                            subtitle: 'View and edit your persona',
                            onTap: () => Navigator.pushNamed(context, AppRoutes.performa),
                          ),
                          TileDivider(isDark: isDark),
                          SettingsNavigationTile(
                            isDark: isDark,
                            iconBg: const Color(0xFF38BDF8).withAlpha(51),
                            iconColor: const Color(0xFF38BDF8),
                            icon: Icons.tune_rounded,
                            title: 'Preferences',
                            subtitle: 'Theme, colors, language',
                            onTap: () => Navigator.pushNamed(context, AppRoutes.preferences),
                          ),
                          TileDivider(isDark: isDark),
                          SettingsNavigationTile(
                            isDark: isDark,
                            iconBg: const Color(0xFFFB7185).withAlpha(51),
                            iconColor: const Color(0xFFFB7185),
                            icon: Icons.chat_bubble_outline_rounded,
                            title: 'Assistant',
                            subtitle: 'Tones and conversation flow',
                            onTap: () => Navigator.pushNamed(context, AppRoutes.assistant),
                          ),
                          TileDivider(isDark: isDark),
                          SettingsNavigationTile(
                            isDark: isDark,
                            iconBg: cs.primary.withAlpha(51),
                            iconColor: cs.primary,
                            icon: Icons.mic_rounded,
                            title: 'Voice Assistant',
                            subtitle: 'Wake word and voice modes',
                            onTap: () => Navigator.pushNamed(context, AppRoutes.voiceAssistant),
                          ),
                          TileDivider(isDark: isDark),
                          SettingsNavigationTile(
                            isDark: isDark,
                            iconBg: Colors.grey.withAlpha(51),
                            iconColor: isDark
                                ? AppColors.slate300
                                : Colors.grey.shade600,
                            icon: Icons.storage_outlined,
                            title: 'Data Management',
                            subtitle: 'Storage and cache',
                            onTap: () => Navigator.pushNamed(context, AppRoutes.data),
                          ),
                          TileDivider(isDark: isDark),
                          SettingsNavigationTile(
                            isDark: isDark,
                            iconBg: Colors.grey.withAlpha(51),
                            iconColor: isDark
                                ? AppColors.slate300
                                : Colors.grey.shade600,
                            icon: Icons.lock_outline,
                            title: 'Permissions',
                            subtitle: 'OS permissions and access',
                            onTap: () => Navigator.pushNamed(context, AppRoutes.permissions),
                          ),
                          TileDivider(isDark: isDark),
                          SettingsNavigationTile(
                            isDark: isDark,
                            iconBg: AppColors.primary.withAlpha(38),
                            iconColor: AppColors.primary,
                            icon: Icons.help_outline_rounded,
                            title: 'Help & tips',
                            subtitle: 'Per-screen guidance and tutorials',
                            onTap: () => Navigator.pushNamed(context, AppRoutes.help),
                          ),
                          TileDivider(isDark: isDark),
                          SettingsNavigationTile(
                            isDark: isDark,
                            iconBg: AppColors.amber.withAlpha(38),
                            iconColor: AppColors.amber,
                            icon: Icons.replay_rounded,
                            title: 'Replay tutorial',
                            subtitle: 'See the welcome carousel again',
                            onTap: () async {
                              await OnboardingService.instance.reset();
                              if (!context.mounted) return;
                              Navigator.pushNamed(
                                context,
                                AppRoutes.onboarding,
                              );
                            },
                          ),
                          TileDivider(isDark: isDark),
                          SettingsNavigationTile(
                            isDark: isDark,
                            iconBg: const Color(0xFF10B981).withAlpha(38),
                            iconColor: const Color(0xFF10B981),
                            icon: Icons.info_outline_rounded,
                            title: 'About & Support',
                            subtitle: 'App info and contact',
                            onTap: () => Navigator.pushNamed(context, AppRoutes.about),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // LOGOUT BUTTON
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _isLoggingOut
                          ? const Center(child: CircularProgressIndicator())
                          : _LogoutButton(onTap: _logout),
                    ),

                    const SizedBox(height: 24),

                    // VERSION FOOTER
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'Bubbles v1.0.5',
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
                            'Your Personal Intelligence Companion',
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
                  ],
                ),
              ),
            ),
          ],
        ),
    );
  }
}

// Settings Navigation Tile

class SettingsNavigationTile extends StatelessWidget {
  final bool isDark;
  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const SettingsNavigationTile({
    super.key,
    required this.isDark,
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? AppColors.slate600 : AppColors.slate400,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Profile Hero Card
class _ProfileHeroCard extends StatelessWidget {
  final bool isDark;
  final ColorScheme cs;

  const _ProfileHeroCard({required this.isDark, required this.cs});

  void _showProfileOptions(BuildContext context, bool isDark) {
    AppSheet.show<void>(
      context: context,
      title: 'Profile Options',
      icon: Icons.account_circle_outlined,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OptionTile(
            isDark: isDark,
            icon: Icons.edit_outlined,
            title: 'Edit Profile',
            subtitle: 'Update your name and information',
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.profileCompletion);
            },
          ),
          const SizedBox(height: 12),
          _OptionTile(
            isDark: isDark,
            icon: Icons.workspace_premium_outlined,
            title: 'Manage Subscription',
            subtitle: 'View plans and billing',
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.subscription);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final email = user?.email ?? 'user@bubbles.ai';
    final name = user?.userMetadata?['full_name'] ?? email.split('@').first;
    final avatarUrl = user?.userMetadata?['avatar_url'];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showProfileOptions(context, isDark),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.glassWhite : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(
              color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
            ),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withAlpha(8),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ],
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cs.primary, cs.primary.withAlpha(150)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  image: avatarUrl != null
                      ? DecorationImage(
                          image: CachedNetworkImageProvider(avatarUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: avatarUrl == null
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                        style: GoogleFonts.manrope(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.primary.withAlpha(60)),
                ),
                child: Text(
                  'FREE',
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionTile({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: isDark ? AppColors.glassWhite : Colors.grey.withAlpha(10),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cs.primary, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: isDark ? AppColors.slate600 : AppColors.slate400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Logout Button
class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;

  const _LogoutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.glassWhite : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.logout_rounded,
                  color: AppColors.error, size: 20),
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
      ),
    );
  }
}
