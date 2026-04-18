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
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (Route<dynamic> route) => false);
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

  void _showComingSoon(BuildContext context, String feature) =>
      showComingSoon(context, feature);

  void _showContactSheet(BuildContext context, bool isDark) =>
      showContactSheet(context, isDark);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null &&
            details.primaryVelocity! < -300) {
          // Swipe Left -> go back
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : AppColors.backgroundLight,
        body: Stack(
          children: [
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
                      colors: [
                        Theme.of(context).colorScheme.primary.withAlpha(38),
                        Colors.transparent,
                      ],
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
                      colors: [
                        Theme.of(context).colorScheme.primary.withAlpha(26),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
            SafeArea(
              child: Column(
                children: [
                  // --- Header ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Go back',
                          icon: Icon(
                            Icons.arrow_back,
                            size: 28,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Text(
                            'Done',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Settings',
                        style: GoogleFonts.manrope(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : AppColors.slate900,
                        ),
                      ),
                    ),
                  ),

                  // --- Content ---
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ACCOUNT SECTION
                          SectionLabel(label: 'Account'),
                          GroupedContainer(
                            isDark: isDark,
                            children: [
                              // Profile Tile
                              ProfileTile(isDark: isDark),
                              TileDivider(isDark: isDark),
                              // Subscription
                              SettingsTile(
                                isDark: isDark,
                                iconBg: Theme.of(
                                  context,
                                ).colorScheme.secondary.withAlpha(51),
                                iconColor: Theme.of(
                                  context,
                                ).colorScheme.secondary,
                                icon: Icons.diamond_outlined,
                                title: 'Subscription',
                                trailing: Text(
                                  'Free Plan',
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                                onTap: () =>
                                    Navigator.pushNamed(context, AppRoutes.subscription),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // PREFERENCES SECTION
                          SectionLabel(label: 'Preferences'),
                          GroupedContainer(
                            isDark: isDark,
                            children: [
                              Consumer<ThemeProvider>(
                                builder: (context, themeProvider, _) =>
                                    SettingsTile(
                                      isDark: isDark,
                                      iconBg: const Color(
                                        0xFF38BDF8,
                                      ).withAlpha(51),
                                      iconColor: const Color(0xFF38BDF8),
                                      icon: Icons.brightness_medium_outlined,
                                      title: 'Theme Mode',
                                      trailing: Text(
                                        themeProvider.themeMode ==
                                                ThemeMode.system
                                            ? 'System'
                                            : themeProvider.themeMode ==
                                                  ThemeMode.dark
                                            ? 'Dark'
                                            : 'Light',
                                        style: GoogleFonts.manrope(
                                          fontSize: 13,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                      onTap: () => _showThemeModePicker(
                                        context,
                                        themeProvider,
                                      ),
                                    ),
                              ),
                              TileDivider(isDark: isDark),
                              Consumer<ThemeProvider>(
                                builder: (context, themeProvider, _) =>
                                    SettingsTile(
                                      isDark: isDark,
                                      iconBg: themeProvider.seedColor.withAlpha(
                                        51,
                                      ),
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
                                      onTap: () => _showColorPicker(
                                        context,
                                        themeProvider,
                                      ),
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
                                    fontSize: 13,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                                                  onTap: () => Navigator.pushNamed(context, AppRoutes.language),
                                ),
                                TileDivider(isDark: isDark),
                                Consumer<SettingsProvider>(
                                  builder: (context, settingsProvider, _) =>
                                      SettingsTile(
                                        isDark: isDark,
                                        iconBg: const Color(0xFFFB7185).withAlpha(51),
                                        iconColor: const Color(0xFFFB7185),
                                        icon: Icons.chat_bubble_outline,
                                        title: 'Live Tone',
                                        trailing: Text(
                                          settingsProvider.defaultLiveTone[0].toUpperCase() + settingsProvider.defaultLiveTone.substring(1),
                                          style: GoogleFonts.manrope(
                                            fontSize: 13,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                        onTap: () => _showLiveTonePicker(
                                          context,
                                          settingsProvider,
                                        ),
                                      ),
                                ),
                                TileDivider(isDark: isDark),
                                Consumer<SettingsProvider>(
                                  builder: (context, settingsProvider, _) =>
                                      SettingsTile(
                                        isDark: isDark,
                                        iconBg: const Color(0xFF60A5FA).withAlpha(51),
                                        iconColor: const Color(0xFF60A5FA),
                                        icon: Icons.person_outline,
                                        title: 'Consultant Tone',
                                        trailing: Text(
                                          settingsProvider.defaultConsultantTone[0].toUpperCase() + settingsProvider.defaultConsultantTone.substring(1),
                                          style: GoogleFonts.manrope(
                                            fontSize: 13,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                        onTap: () => _showConsultantTonePicker(
                                          context,
                                          settingsProvider,
                                        ),
                                      ),
                                ),
                                TileDivider(isDark: isDark),
                                Consumer<SettingsProvider>(
                                  builder: (context, settingsProvider, _) =>
                                      ToggleTile(
                                        isDark: isDark,
                                        iconBg: const Color(0xFFF59E0B).withAlpha(51),
                                        iconColor: const Color(0xFFF59E0B),
                                        icon: Icons.question_answer_outlined,
                                        title: 'Always ask for tone when starting',
                                        value: settingsProvider.alwaysPromptForTone,
                                        onChanged: (val) => settingsProvider.setAlwaysPromptForTone(val),
                                      ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 24),

                          // VOICE ASSISTANT
                          SectionLabel(label: 'Voice Assistant'),
                          Consumer<VoiceAssistantService>(
                            builder: (context, voice, _) {
                              return GroupedContainer(
                                isDark: isDark,
                                children: [
                                  ToggleTile(
                                    isDark: isDark,
                                    iconBg: Theme.of(
                                      context,
                                    ).colorScheme.primary.withAlpha(51),
                                    iconColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
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
                                    iconColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    icon: Icons.record_voice_over_outlined,
                                    title: 'Voice Mode',
                                    trailing: Text(
                                      voice.voiceMode.name[0].toUpperCase() +
                                          voice.voiceMode.name.substring(1),
                                      style: GoogleFonts.manrope(
                                        fontSize: 13,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                    onTap: () =>
                                        _showVoiceModePicker(context, voice),
                                  ),
                                  TileDivider(isDark: isDark),
                                  VoiceEnrollmentSection(isDark: isDark),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),

                          // PRIVACY
                          SectionLabel(label: 'Privacy'),
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
                                onTap: () =>
                                    Navigator.pushNamed(context, AppRoutes.data),
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
                                onTap: () =>
                                    Navigator.pushNamed(context, AppRoutes.permissions),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // NOTIFICATIONS
                          SectionLabel(label: 'Notifications'),
                          Consumer<ConnectionService>(
                            builder: (context, conn, _) => GroupedContainer(
                              isDark: isDark,
                              children: [
                                ToggleTile(
                                  isDark: isDark,
                                  iconBg: const Color(0xFFF43F5E).withAlpha(51),
                                  iconColor: const Color(0xFFF43F5E),
                                  icon: Icons.notifications_outlined,
                                  title: 'Push Notifications',
                                  value: _notificationsGranted,
                                  onChanged: _toggleNotifications,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          // ABOUT & SUPPORT
                          SectionLabel(label: 'About & Support'),
                          GroupedContainer(
                            isDark: isDark,
                            children: [
                              SettingsTile(
                                isDark: isDark,
                                iconBg: Theme.of(
                                  context,
                                ).colorScheme.primary.withAlpha(38),
                                iconColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                icon: Icons.info_outline_rounded,
                                title: 'About Bubbles',
                                onTap: () =>
                                    Navigator.pushNamed(context, '/about'),
                              ),
                              TileDivider(isDark: isDark),
                              SettingsTile(
                                isDark: isDark,
                                iconBg: const Color(0xFF10B981).withAlpha(38),
                                iconColor: const Color(0xFF10B981),
                                icon: Icons.mail_outline_rounded,
                                title: 'Contact Us',
                                onTap: () => _showContactSheet(context, isDark),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),

                          // LOG OUT
                          _isLoggingOut
                              ? const Center(child: CircularProgressIndicator())
                              : GestureDetector(
                                  onTap: _logout,
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppColors.glassWhite
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.xxl,
                                      ),
                                      border: Border.all(
                                        color: isDark
                                            ? AppColors.glassBorder
                                            : Colors.grey.shade200,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Log Out',
                                        style: GoogleFonts.manrope(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                          const SizedBox(height: 20),

                          // Version
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
                          const SizedBox(height: 30),
                        ],
                      ),
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

  void _showThemeModePicker(
    BuildContext context,
    ThemeProvider themeProvider,
  ) => showThemeModePicker(context, themeProvider);

  void _showColorPicker(BuildContext context, ThemeProvider themeProvider) =>
      showColorPicker(context, themeProvider);

  void _showVoiceModePicker(
    BuildContext context,
    VoiceAssistantService voice,
  ) => showVoiceModePicker(context, voice);

  void _showLiveTonePicker(BuildContext context, SettingsProvider p) =>
      showLiveTonePicker(context, p);

  void _showConsultantTonePicker(BuildContext context, SettingsProvider p) =>
      showConsultantTonePicker(context, p);
}

