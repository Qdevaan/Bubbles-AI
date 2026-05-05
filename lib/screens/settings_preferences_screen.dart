import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/design_tokens.dart';
import '../widgets/animated_background.dart';
import '../widgets/settings/settings_widgets.dart';
import '../widgets/settings/settings_dialogs.dart';

class SettingsPreferencesScreen extends StatelessWidget {
  const SettingsPreferencesScreen({super.key});

  void _showThemeModePicker(BuildContext context, ThemeProvider themeProvider) =>
      showThemeModePicker(context, themeProvider);

  void _showColorPicker(BuildContext context, ThemeProvider themeProvider) =>
      showColorPicker(context, themeProvider);

  void _showLanguagePicker(BuildContext context, SettingsProvider p) =>
      showLanguagePicker(context, p);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Stack(
        children: [
          Positioned.fill(child: AnimatedAmbientBackground(isDark: isDark)),
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 20,
                            color: isDark ? Colors.white : AppColors.slate900,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Preferences',
                                style: GoogleFonts.manrope(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : AppColors.slate900,
                                ),
                              ),
                              Text(
                                'Customize your app experience.',
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),

                // Appearance section
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 10),
                          child: Text(
                            'APPEARANCE',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: isDark ? AppColors.slate400 : AppColors.slate500,
                            ),
                          ),
                        ),
                        GroupedContainer(
                          isDark: isDark,
                          children: [
                            Consumer<ThemeProvider>(
                              builder: (context, tp, _) => SettingsTile(
                                isDark: isDark,
                                iconBg: const Color(0xFF38BDF8).withAlpha(51),
                                iconColor: const Color(0xFF38BDF8),
                                icon: Icons.brightness_medium_outlined,
                                title: 'Theme Mode',
                                trailing: Text(
                                  tp.themeMode == ThemeMode.system
                                      ? 'System'
                                      : tp.themeMode == ThemeMode.dark
                                          ? 'Dark'
                                          : 'Light',
                                  style: GoogleFonts.manrope(
                                      fontSize: 13, color: AppColors.textMuted),
                                ),
                                onTap: () => _showThemeModePicker(context, tp),
                              ),
                            ),
                            TileDivider(isDark: isDark),
                            Consumer<ThemeProvider>(
                              builder: (context, tp, _) => SettingsTile(
                                isDark: isDark,
                                iconBg: tp.seedColor.withAlpha(51),
                                iconColor: tp.seedColor,
                                icon: Icons.color_lens_outlined,
                                title: 'Accent Color',
                                trailing: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: tp.seedColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                onTap: () => _showColorPicker(context, tp),
                              ),
                            ),
                            TileDivider(isDark: isDark),
                            Consumer<SettingsProvider>(
                              builder: (context, sp, _) => SettingsTile(
                                isDark: isDark,
                                iconBg: const Color(0xFF34D399).withAlpha(51),
                                iconColor: const Color(0xFF34D399),
                                icon: Icons.translate,
                                title: 'Language',
                                trailing: Text(
                                  sp.locale.languageCode == 'en'
                                      ? 'English'
                                      : sp.locale.languageCode == 'ur'
                                          ? 'Urdu'
                                          : 'Arabic',
                                  style: GoogleFonts.manrope(
                                      fontSize: 13, color: AppColors.textMuted),
                                ),
                                onTap: () => _showLanguagePicker(context, sp),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),

                // Home Screen section
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 10),
                          child: Text(
                            'HOME SCREEN',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: isDark ? AppColors.slate400 : AppColors.slate500,
                            ),
                          ),
                        ),
                        Consumer<SettingsProvider>(
                          builder: (context, sp, _) => GroupedContainer(
                            isDark: isDark,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                child: Column(
                                  children: [
                                    _HomePickerRow(
                                      label: 'Session hero',
                                      options: const ['orb', 'card'],
                                      labels: const ['Orb', 'Card'],
                                      selected: sp.sessionHeroStyle,
                                      onChanged: sp.setSessionHeroStyle,
                                      isDark: isDark,
                                    ),
                                    const SizedBox(height: 16),
                                    _HomePickerRow(
                                      label: 'Quick actions',
                                      options: const ['pills', 'icons', 'cards'],
                                      labels: const ['Pills', 'Icons', 'Cards'],
                                      selected: sp.quickActionsStyle,
                                      onChanged: sp.setQuickActionsStyle,
                                      isDark: isDark,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Home Picker Row ────────────────────────────────────────────────────────────
class _HomePickerRow extends StatelessWidget {
  final String label;
  final List<String> options;
  final List<String> labels;
  final String selected;
  final Future<void> Function(String) onChanged;
  final bool isDark;

  const _HomePickerRow({
    required this.label,
    required this.options,
    required this.labels,
    required this.selected,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.slate900,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          children: List.generate(options.length, (i) {
            final isSelected = selected == options[i];
            return GestureDetector(
              onTap: () => onChanged(options[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? primary.withAlpha(25) : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: isSelected
                        ? primary
                        : (isDark
                            ? AppColors.glassBorder
                            : Colors.grey.shade300),
                  ),
                ),
                child: Text(
                  labels[i],
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? primary
                        : (isDark ? AppColors.slate400 : AppColors.slate500),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
