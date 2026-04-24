import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../theme/design_tokens.dart';
import '../widgets/animated_background.dart';
import '../widgets/settings/settings_widgets.dart';
import '../widgets/settings/settings_dialogs.dart';

class SettingsAssistantScreen extends StatelessWidget {
  const SettingsAssistantScreen({super.key});

  String _toneLabel(String tone) {
    switch (tone) {
      case 'formal':
        return 'Formal';
      case 'semi-formal':
        return 'Semi-formal';
      case 'casual':
        return 'Casual';
      default:
        return 'Casual';
    }
  }

  void _showLiveTonePicker(BuildContext context, SettingsProvider p) =>
      showLiveTonePicker(context, p);

  void _showConsultantTonePicker(BuildContext context, SettingsProvider p) =>
      showConsultantTonePicker(context, p);

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
                                'Assistant',
                                style: GoogleFonts.manrope(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : AppColors.slate900,
                                ),
                              ),
                              Text(
                                'Configure AI assistant behavior.',
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
                    child: Consumer<SettingsProvider>(
                      builder: (context, settingsProvider, _) => GroupedContainer(
                        isDark: isDark,
                        children: [
                          SettingsTile(
                            isDark: isDark,
                            iconBg: const Color(0xFFFB7185).withAlpha(51),
                            iconColor: const Color(0xFFFB7185),
                            icon: Icons.chat_bubble_outline,
                            title: 'Live Tone',
                            trailing: Text(
                              _toneLabel(settingsProvider.defaultLiveTone),
                              style: GoogleFonts.manrope(
                                  fontSize: 13, color: AppColors.textMuted),
                            ),
                            onTap: () => _showLiveTonePicker(context, settingsProvider),
                          ),
                          TileDivider(isDark: isDark),
                          SettingsTile(
                            isDark: isDark,
                            iconBg: const Color(0xFF60A5FA).withAlpha(51),
                            iconColor: const Color(0xFF60A5FA),
                            icon: Icons.person_outline,
                            title: 'Consultant Tone',
                            trailing: Text(
                              _toneLabel(settingsProvider.defaultConsultantTone),
                              style: GoogleFonts.manrope(
                                  fontSize: 13, color: AppColors.textMuted),
                            ),
                            onTap: () => _showConsultantTonePicker(context, settingsProvider),
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
                                settingsProvider.setAlwaysPromptForTone(val),
                          ),
                        ],
                      ),
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
