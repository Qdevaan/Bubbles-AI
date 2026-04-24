import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/voice_assistant_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/animated_background.dart';
import '../widgets/settings/settings_widgets.dart';
import '../widgets/settings/settings_dialogs.dart';

class SettingsVoiceAssistantScreen extends StatelessWidget {
  const SettingsVoiceAssistantScreen({super.key});

  void _showVoiceModePicker(BuildContext context, VoiceAssistantService voice) =>
      showVoiceModePicker(context, voice);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

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
                                'Voice Assistant',
                                style: GoogleFonts.manrope(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : AppColors.slate900,
                                ),
                              ),
                              Text(
                                'Manage wake word and voice features.',
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
                    child: Consumer<VoiceAssistantService>(
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
                            onChanged: (val) => voice.setWakeWordEnabled(val),
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
                                  fontSize: 13, color: AppColors.textMuted),
                            ),
                            onTap: () => _showVoiceModePicker(context, voice),
                          ),
                          TileDivider(isDark: isDark),
                          VoiceEnrollmentSection(isDark: isDark),
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
