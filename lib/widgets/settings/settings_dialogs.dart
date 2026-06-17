// Purpose: Reusable dialog widgets for the settings screens — confirmation dialogs for destructive actions.
import '../../providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_tokens.dart';
import '../../providers/theme_provider.dart';
import '../../services/voice_assistant_service.dart';
import '../app_dialog.dart';
import '../app_sheet.dart';
import 'settings_widgets.dart';

/// Shows a contact-us bottom sheet.
void showContactSheet(BuildContext context, bool isDark) {
  final primary = Theme.of(context).colorScheme.primary;
  AppSheet.show<void>(
    context: context,
    title: 'Contact Us',
    subtitle:
        'Have questions, feedback, or need support? Reach out to the Bubbles team.',
    icon: Icons.support_agent_rounded,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
}

/// Shows a theme mode picker dialog (System / Light / Dark).
void showThemeModePicker(BuildContext context, ThemeProvider themeProvider) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  AppDialog.show<void>(
    context: context,
    title: 'Select Theme Mode',
    icon: Icons.palette_outlined,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
      ],
    ),
    actions: [
      AppDialogAction(
        label: 'Close',
        onTap: () => Navigator.of(context).pop(),
      ),
    ],
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
  const swatches = <Color>[
    AppColors.primary,           // slate-600 (new default)
    Color(0xFF13BDEC),           // legacy Bubbles cyan
    Colors.blueAccent,
    Colors.redAccent,
    Colors.greenAccent,
    Colors.orangeAccent,
    Colors.purpleAccent,
    Colors.tealAccent,
    Colors.pinkAccent,
    Colors.amberAccent,
    Colors.indigoAccent,
  ];
  AppDialog.show<void>(
    context: context,
    title: 'Accent Color',
    icon: Icons.color_lens_outlined,
    content: Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: swatches.map((color) {
        final isSelected =
            themeProvider.seedColor.toARGB32() == color.toARGB32();
        return GestureDetector(
          onTap: () {
            themeProvider.setThemeColor(color);
            Navigator.of(context).pop();
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
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null,
          ),
        );
      }).toList(),
    ),
    actions: [
      AppDialogAction(
        label: 'Cancel',
        onTap: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

/// Shows a voice mode picker bottom sheet (Male / Female / Jarvis).
void showVoiceModePicker(BuildContext context, VoiceAssistantService voice) {
  final primary = Theme.of(context).colorScheme.primary;
  AppSheet.show<void>(
    context: context,
    title: 'Select Voice Mode',
    icon: Icons.record_voice_over_outlined,
    child: StatefulBuilder(
      builder: (ctx, setSheetState) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        VoiceMode selectedMode = voice.voiceMode;

        Widget buildCard({
          required VoiceMode mode,
          required IconData icon,
          required String label,
          required Color color,
        }) {
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
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
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

        return Row(
          children: [
            buildCard(
              mode: VoiceMode.male,
              icon: Icons.man_rounded,
              label: 'Male',
              color: primary,
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
              color: primary,
            ),
          ],
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
  _showRadioPicker(
    context: context,
    title: 'Live Session Tone',
    icon: Icons.chat_bubble_outline,
    options: const ['Casual', 'Semi-formal', 'Formal'],
    isSelected: (tone) =>
        settingsProvider.defaultLiveTone.toLowerCase() == tone.toLowerCase(),
    onSelected: (tone) =>
        settingsProvider.setDefaultLiveTone(tone.toLowerCase()),
  );
}

/// Shows a consultant session tone picker dialog.
void showConsultantTonePicker(
  BuildContext context,
  SettingsProvider settingsProvider,
) {
  _showRadioPicker(
    context: context,
    title: 'Consultant Session Tone',
    icon: Icons.person_outline,
    options: const ['Casual', 'Semi-formal', 'Formal'],
    isSelected: (tone) =>
        settingsProvider.defaultConsultantTone.toLowerCase() ==
        tone.toLowerCase(),
    onSelected: (tone) =>
        settingsProvider.setDefaultConsultantTone(tone.toLowerCase()),
  );
}

/// Shows a quick actions layout style picker dialog.
void showQuickActionsStylePicker(
  BuildContext context,
  SettingsProvider settingsProvider,
) {
  const styleOptions = {
    'list': 'List (One in a line)',
    'grid': 'Grid (Two in a line)',
    'icons': 'Icons (App-like)',
  };
  final keys = styleOptions.keys.toList();
  _showRadioPicker(
    context: context,
    title: 'Quick Actions Layout',
    icon: Icons.grid_view_rounded,
    options: keys,
    labelFor: (k) => styleOptions[k]!,
    isSelected: (k) => settingsProvider.quickActionsStyle == k,
    onSelected: (k) => settingsProvider.setQuickActionsStyle(k),
  );
}

/// Shows a language picker dialog.
void showLanguagePicker(BuildContext context, SettingsProvider settingsProvider) {
  const locales = [
    (Locale('en'), 'English', '🇬🇧'),
    (Locale('ur'), 'اردو', '🇵🇰'),
    (Locale('ar'), 'العربية', '🇸🇦'),
  ];
  _showRadioPicker<Locale>(
    context: context,
    title: 'Select Language',
    icon: Icons.translate_rounded,
    options: locales.map((e) => e.$1).toList(),
    labelFor: (l) {
      final entry = locales.firstWhere((e) => e.$1 == l);
      return '${entry.$3}  ${entry.$2}';
    },
    isSelected: (l) =>
        settingsProvider.locale.languageCode == l.languageCode,
    onSelected: (l) => settingsProvider.setLocale(l),
  );
}

/// Shared radio-style single-select picker used by tone/quick-actions/language.
void _showRadioPicker<T>({
  required BuildContext context,
  required String title,
  required IconData icon,
  required List<T> options,
  required bool Function(T) isSelected,
  required void Function(T) onSelected,
  String Function(T)? labelFor,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  AppDialog.show<void>(
    context: context,
    title: title,
    icon: icon,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final opt in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildToneOption(
              context: context,
              title: labelFor != null ? labelFor(opt) : opt.toString(),
              isSelected: isSelected(opt),
              isDark: isDark,
              onTap: () {
                onSelected(opt);
                Navigator.of(context).pop();
              },
            ),
          ),
      ],
    ),
    actions: [
      AppDialogAction(
        label: 'Cancel',
        onTap: () => Navigator.of(context).pop(),
      ),
    ],
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
