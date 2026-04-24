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

  void _showQuickActionsStylePicker(BuildContext context, SettingsProvider p) =>
      showQuickActionsStylePicker(context, p);

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
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child: GroupedContainer(
                      isDark: isDark,
                      children: [
                        Consumer<ThemeProvider>(
                          builder: (context, themeProvider, _) => SettingsTile(
                            isDark: isDark,
                            iconBg: const Color(0xFF38BDF8).withAlpha(51),
                            iconColor: const Color(0xFF38BDF8),
                            icon: Icons.brightness_medium_outlined,
                            title: 'Theme Mode',
                            trailing: Text(
                              themeProvider.themeMode == ThemeMode.system
                                  ? 'System'
                                  : themeProvider.themeMode == ThemeMode.dark
                                      ? 'Dark'
                                      : 'Light',
                              style: GoogleFonts.manrope(
                                  fontSize: 13, color: AppColors.textMuted),
                            ),
                            onTap: () => _showThemeModePicker(context, themeProvider),
                          ),
                        ),
                        TileDivider(isDark: isDark),
                        Consumer<ThemeProvider>(
                          builder: (context, themeProvider, _) => SettingsTile(
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
                            onTap: () => _showColorPicker(context, themeProvider),
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
                        TileDivider(isDark: isDark),
                        Consumer<SettingsProvider>(
                          builder: (context, settingsProvider, _) => SettingsTile(
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
                            onTap: () => _showQuickActionsStylePicker(context, settingsProvider),
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
