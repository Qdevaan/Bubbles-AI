import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/voice_assistant_service.dart';
import '../../theme/design_tokens.dart';

/// Animated status chip showing the current voice assistant state.
class VoiceStatusChip extends StatelessWidget {
  final VoiceAssistantState state;
  final Animation<double> pulseAnimation;
  final bool isDark;

  const VoiceStatusChip({
    super.key,
    required this.state,
    required this.pulseAnimation,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    String label;
    Color accentColor;
    IconData icon;

    switch (state) {
      case VoiceAssistantState.listening:
        label = 'LISTENING';
        accentColor = Theme.of(context).colorScheme.primary;
        icon = Icons.hearing_rounded;
        break;
      case VoiceAssistantState.processing:
        label = 'THINKING';
        accentColor = AppColors.warning;
        icon = Icons.psychology_rounded;
        break;
      case VoiceAssistantState.speaking:
        label = 'SPEAKING';
        accentColor = AppColors.success;
        icon = Icons.volume_up_rounded;
        break;
      default:
        label = 'READY';
        accentColor = Theme.of(context).colorScheme.primary;
        icon = Icons.mic_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.full),
        color: accentColor.withAlpha(31),
        border: Border.all(color: accentColor.withAlpha(64), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated pulse dot
          AnimatedBuilder(
            animation: pulseAnimation,
            builder: (context, _) {
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withAlpha(
                        ((0.5 * (pulseAnimation.value - 1.0) / 0.2) * 255).round(),
                      ),
                      blurRadius: 6,
                      spreadRadius: 2 * (pulseAnimation.value - 1.0) / 0.2,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Icon(icon, color: accentColor, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accentColor,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Text display showing transcription, response, or idle prompt.
class VoiceTextDisplay extends StatelessWidget {
  final VoiceAssistantService assistant;
  final bool isDark;

  const VoiceTextDisplay({
    super.key,
    required this.assistant,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    String displayText;
    FontWeight weight = FontWeight.w500;
    double fontSize = 14;
    Color textColor;

    switch (assistant.state) {
      case VoiceAssistantState.listening:
        displayText = assistant.partialText.isNotEmpty
            ? '"${assistant.partialText}"'
            : 'Go ahead, I\'m listening...';
        textColor = isDark ? AppColors.slate300 : AppColors.slate600;
        break;
      case VoiceAssistantState.processing:
        displayText = '"${assistant.partialText}"';
        textColor = isDark ? AppColors.slate300 : AppColors.slate600;
        break;
      case VoiceAssistantState.speaking:
        displayText = assistant.lastResponse;
        weight = FontWeight.w500;
        fontSize = 15;
        textColor = isDark ? Colors.white : AppColors.slate900;
        break;
      default:
        displayText = 'Say "Hey Bubbles" to begin';
        textColor = isDark ? AppColors.textSecondary : AppColors.textMuted;
    }

    return AnimatedSwitcher(
      duration: AppDurations.normal,
      child: Text(
        displayText,
        key: ValueKey(displayText),
        textAlign: TextAlign.center,
        style: GoogleFonts.manrope(
          fontSize: fontSize,
          fontWeight: weight,
          color: textColor,
          height: 1.5,
        ),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Bottom bar with voice mode badge and dismiss button.
class VoiceBottomBar extends StatelessWidget {
  final VoiceAssistantService assistant;
  final bool isDark;

  const VoiceBottomBar({
    super.key,
    required this.assistant,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildVoiceModeBadge(context),
        const Spacer(),
        // Dismiss button
        Semantics(
          button: true,
          label: 'Dismiss voice assistant',
          child: GestureDetector(
            onTap: () => assistant.hideOverlay(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                color: isDark
                    ? Colors.white.withAlpha(15)
                    : Colors.grey.shade100,
                border: Border.all(
                  color: isDark
                      ? Colors.white.withAlpha(20)
                      : Colors.grey.shade200,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: isDark ? AppColors.textSecondary : AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Dismiss',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textSecondary
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceModeBadge(BuildContext context) {
    final mode = assistant.voiceMode;
    IconData icon;
    String label;

    switch (mode) {
      case VoiceMode.male:
        icon = Icons.record_voice_over_rounded;
        label = 'Male';
        break;
      case VoiceMode.female:
        icon = Icons.record_voice_over_rounded;
        label = 'Female';
        break;
      case VoiceMode.neutral:
        icon = Icons.smart_toy_rounded;
        label = 'Jarvis';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        color: Theme.of(context).colorScheme.primary.withAlpha(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withAlpha(38),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
