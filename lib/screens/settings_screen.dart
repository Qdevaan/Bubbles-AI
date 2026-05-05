import 'dart:async';
import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../theme/design_tokens.dart';
import '../services/app_cache_service.dart';
import '../services/auth_service.dart';
import '../providers/settings_provider.dart';
import '../routes/app_routes.dart';
import '../widgets/settings/settings_widgets.dart';
import '../widgets/animated_background.dart';

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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0),
                child: Column(
                  children: [
                    // ── Header ────────────────────────────────────────────
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

                    const SizedBox(height: 16),

                    // ── Profile Hero Card ─────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ProfileHeroCard(isDark: isDark, cs: cs),
                    ),

                    const SizedBox(height: 24),


                    // ── Content ───────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GroupedContainer(
                        isDark: isDark,
                        children: [
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
                          Builder(builder: (ctx) {
                            final sp = ctx.watch<SettingsProvider>();
                            final enrolled = sp.voiceEnrolled;
                            final samples = sp.voiceSamplesCount;
                            return SettingsNavigationTile(
                              isDark: isDark,
                              iconBg: enrolled
                                  ? Colors.green.withAlpha(40)
                                  : cs.primary.withAlpha(51),
                              iconColor: enrolled ? Colors.green : cs.primary,
                              icon: enrolled
                                  ? Icons.verified_rounded
                                  : Icons.record_voice_over_rounded,
                              title: 'Voice Enrollment',
                              subtitle: enrolled
                                  ? '$samples sample${samples == 1 ? '' : 's'} · active'
                                  : 'Identify your voice in sessions',
                              onTap: () => Navigator.pushNamed(
                                  context, AppRoutes.voiceEnrollment),
                            );
                          }),
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

                    const Spacer(),

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

// ── Settings Navigation Tile ──────────────────────────────────────────

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
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                    Text(
                      subtitle,
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

// ── Profile Hero Card ──────────────────────────────────────────────────────────
class _ProfileHeroCard extends StatelessWidget {
  final bool isDark;
  final ColorScheme cs;

  const _ProfileHeroCard({required this.isDark, required this.cs});

  void _showProfileOptions(BuildContext context, bool isDark) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.backgroundDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.slate700 : AppColors.slate200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Profile Options',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
            const SizedBox(height: 24),
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
                          image: NetworkImage(avatarUrl),
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
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
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
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                    Text(
                      subtitle,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: isDark ? AppColors.slate400 : AppColors.slate500,
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
