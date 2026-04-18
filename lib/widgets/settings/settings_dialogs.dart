import 'dart:ui';
import '../../providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_tokens.dart';
import '../../providers/theme_provider.dart';
import '../../services/voice_assistant_service.dart';
import '../glass_morphism.dart';
import 'settings_widgets.dart';

/// Shows a "coming soon" snackbar for a feature.
void showComingSoon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('$feature is coming soon!'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Shows a contact-us bottom sheet.
void showContactSheet(BuildContext context, bool isDark) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) {
      final primary = Theme.of(context).colorScheme.primary;
      return GlassBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.glassBorder : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Contact Us',
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Have questions, feedback, or need support? Reach out to the Bubbles team.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: isDark ? AppColors.slate400 : AppColors.slate500,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ContactRow(
              isDark: isDark,
              icon: Icons.email_outlined,
              iconColor: primary,
              label: 'Email Support',
              value: 'support@bubbles.ai',
            ),
            const SizedBox(height: 12),
            ContactRow(
              isDark: isDark,
              icon: Icons.language_rounded,
              iconColor: const Color(0xFF3B82F6),
              label: 'Website',
              value: 'www.bubbles.ai',
            ),
            const SizedBox(height: 12),
            ContactRow(
              isDark: isDark,
              icon: Icons.bug_report_outlined,
              iconColor: AppColors.warning,
              label: 'Report a Bug',
              value: 'bugs@bubbles.ai',
            ),
          ],
        ),
      );
    },
  );
}

/// Shows a theme mode picker dialog (System / Light / Dark).
void showThemeModePicker(BuildContext context, ThemeProvider themeProvider) {
  showDialog(
    context: context,
    builder: (ctx) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return GlassDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha(26),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withAlpha(51),
                    ),
                  ),
                  child: Icon(
                    Icons.palette_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Select Theme Mode',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.slate900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildThemeOption(
              context,
              themeProvider,
              title: 'System Default',
              icon: Icons.brightness_auto,
              mode: ThemeMode.system,
              isDark: isDark,
            ),
            const SizedBox(height: 8),
            _buildThemeOption(
              context,
              themeProvider,
              title: 'Light',
              icon: Icons.light_mode,
              mode: ThemeMode.light,
              isDark: isDark,
            ),
            const SizedBox(height: 8),
            _buildThemeOption(
              context,
              themeProvider,
              title: 'Dark',
              icon: Icons.dark_mode,
              mode: ThemeMode.dark,
              isDark: isDark,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Close',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

Widget _buildThemeOption(
  BuildContext context,
  ThemeProvider themeProvider, {
  required String title,
  required IconData icon,
  required ThemeMode mode,
  required bool isDark,
}) {
  final isSelected = themeProvider.themeMode == mode;
  return GestureDetector(
    onTap: () {
      themeProvider.setThemeMode(mode);
      Navigator.pop(context);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withAlpha(26)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withAlpha(76)
              : (isDark ? Colors.white10 : Colors.black12),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : (isDark ? Colors.white70 : Colors.black87),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
          ),
          if (isSelected)
            Icon(
              Icons.check_circle_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
        ],
      ),
    ),
  );
}

/// Shows an accent color picker dialog.
void showColorPicker(BuildContext context, ThemeProvider themeProvider) {
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
                  color: Theme.of(context).colorScheme.primary.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withAlpha(51),
                  ),
                ),
                child: Icon(
                  Icons.color_lens_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Accent Color',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children:
                [
                  AppColors.primary,
                  Colors.blueAccent,
                  Colors.redAccent,
                  Colors.greenAccent,
                  Colors.orangeAccent,
                  Colors.purpleAccent,
                  Colors.tealAccent,
                  Colors.pinkAccent,
                  Colors.amberAccent,
                  Colors.indigoAccent,
                ].map((color) {
                  final isSelected =
                      themeProvider.seedColor.value == color.value;
                  return GestureDetector(
                    onTap: () {
                      themeProvider.setThemeColor(color);
                      Navigator.pop(ctx);
                    },
                    child: AnimatedContainer(
                      duration: AppDurations.fast,
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withAlpha(128),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                  );
                }).toList(),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Shows a voice mode picker bottom sheet (Male / Female / Jarvis).
void showVoiceModePicker(BuildContext context, VoiceAssistantService voice) {
  final isDarkOuter = Theme.of(context).brightness == Brightness.dark;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        VoiceMode selectedMode = voice.voiceMode;

        Widget buildCard({
          required VoiceMode mode,
          required IconData icon,
          required String label,
          required Color color,
        }) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final isSelected = selectedMode == mode;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setSheetState(() => selectedMode = mode);
                voice.setVoiceMode(mode);
                Future.delayed(AppDurations.fast, () {
                  if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                });
              },
              child: AnimatedContainer(
                duration: AppDurations.tooltip,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: isSelected
                      ? color.withAlpha(38)
                      : (isDark
                            ? AppColors.surfaceDarkHighlight
                            : Colors.grey.shade100),
                  border: Border.all(
                    color: isSelected
                        ? color
                        : (isDark
                              ? Colors.white.withAlpha(26)
                              : Colors.grey.shade300),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      color: isSelected
                          ? color
                          : (isDark ? Colors.white54 : Colors.grey),
                      size: 30,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: isSelected
                            ? color
                            : (isDark ? Colors.white54 : Colors.grey),
                      ),
                    ),
                    if (isSelected)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: color,
                          size: 16,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        return GlassBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.glassBorder : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withAlpha(51),
                      ),
                    ),
                    child: Icon(
                      Icons.record_voice_over_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Select Voice Mode',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.slate900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  buildCard(
                    mode: VoiceMode.male,
                    icon: Icons.man_rounded,
                    label: 'Male',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  buildCard(
                    mode: VoiceMode.female,
                    icon: Icons.woman_rounded,
                    label: 'Female',
                    color: Colors.pinkAccent,
                  ),
                  const SizedBox(width: 10),
                  buildCard(
                    mode: VoiceMode.neutral,
                    icon: Icons.smart_toy_rounded,
                    label: 'Jarvis',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    ),
  );
}

/// Shows a live session tone picker dialog.
void showLiveTonePicker(
  BuildContext context,
  SettingsProvider settingsProvider,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final toneOptions = ['Casual', 'Semi-formal', 'Formal'];

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
                  color: Theme.of(context).colorScheme.primary.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withAlpha(51),
                  ),
                ),
                child: Icon(
                  Icons.chat_bubble_outline,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Live Session Tone',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...toneOptions.map((tone) {
            final isSelected =
                settingsProvider.defaultLiveTone.toLowerCase() ==
                tone.toLowerCase();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildToneOption(
                context: context,
                title: tone,
                isSelected: isSelected,
                isDark: isDark,
                onTap: () {
                  settingsProvider.setDefaultLiveTone(tone.toLowerCase());
                  Navigator.pop(ctx);
                },
              ),
            );
          }).toList(),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Shows a consultant session tone picker dialog.
void showConsultantTonePicker(
  BuildContext context,
  SettingsProvider settingsProvider,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final toneOptions = ['Casual', 'Serious'];

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
                  color: Theme.of(context).colorScheme.primary.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withAlpha(51),
                  ),
                ),
                child: Icon(
                  Icons.person_outline,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Consultant Session Tone',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...toneOptions.map((tone) {
            final isSelected =
                settingsProvider.defaultConsultantTone.toLowerCase() ==
                tone.toLowerCase();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildToneOption(
                context: context,
                title: tone,
                isSelected: isSelected,
                isDark: isDark,
                onTap: () {
                  settingsProvider.setDefaultConsultantTone(tone.toLowerCase());
                  Navigator.pop(ctx);
                },
              ),
            );
          }).toList(),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Shows a quick actions layout style picker dialog.
void showQuickActionsStylePicker(
  BuildContext context,
  SettingsProvider settingsProvider,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  // Map internal string values to display titles
  final styleOptions = {
    'list': 'List (One in a line)',
    'grid': 'Grid (Two in a line)',
    'icons': 'Icons (App-like)',
  };

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
                  color: Theme.of(context).colorScheme.primary.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withAlpha(51),
                  ),
                ),
                child: Icon(
                  Icons.grid_view_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Quick Actions Layout',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...styleOptions.entries.map((entry) {
            final styleKey = entry.key;
            final styleName = entry.value;
            final isSelected =
                settingsProvider.quickActionsStyle == styleKey;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildToneOption(
                context: context,
                title: styleName,
                isSelected: isSelected,
                isDark: isDark,
                onTap: () {
                  settingsProvider.setQuickActionsStyle(styleKey);
                  Navigator.pop(ctx);
                },
              ),
            );
          }).toList(),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Helper widget to build tone option rows.
Widget _buildToneOption({
  required BuildContext context,
  required String title,
  required bool isSelected,
  required bool isDark,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withAlpha(26)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withAlpha(76)
              : (isDark ? Colors.white10 : Colors.black12),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 20,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : (isDark ? Colors.white30 : Colors.grey.shade400),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
