import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/voice_assistant_service.dart';
import '../../theme/design_tokens.dart';

/// Visual indicator widget for the voice overlay.
/// Switches between listening orb, processing dots, speaking waves, and idle orb.
class VoiceVisualIndicator extends StatelessWidget {
  final VoiceAssistantState state;
  final Animation<double> pulseAnimation;
  final AnimationController waveController;
  final bool isDark;

  const VoiceVisualIndicator({
    super.key,
    required this.state,
    required this.pulseAnimation,
    required this.waveController,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case VoiceAssistantState.listening:
        return _buildListeningOrb(context);
      case VoiceAssistantState.processing:
        return _buildProcessingIndicator();
      case VoiceAssistantState.speaking:
        return _buildSpeakingWaves();
      default:
        return _buildIdleOrb(context);
    }
  }

  /// Pulsing orb with concentric rings — listening state
  Widget _buildListeningOrb(BuildContext context) {
    return SizedBox(
      height: 90,
      width: 90,
      child: AnimatedBuilder(
        animation: pulseAnimation,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer ring
              Container(
                width: 90 * pulseAnimation.value,
                height: 90 * pulseAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withAlpha(38),
                    width: 1.5,
                  ),
                ),
              ),
              // Middle ring
              Container(
                width: 65 * (1.0 + (pulseAnimation.value - 1.0) * 0.6),
                height: 65 * (1.0 + (pulseAnimation.value - 1.0) * 0.6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withAlpha(20),
                ),
              ),
              // Center orb
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primary.withAlpha(200),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withAlpha(102),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Sequenced dots — processing state
  Widget _buildProcessingIndicator() {
    return SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(5, (i) {
          return AnimatedBuilder(
            animation: waveController,
            builder: (context, _) {
              final phase = (waveController.value * 2 * pi) + (i * 1.2);
              final scale = 0.6 + (sin(phase) + 1) * 0.35;
              final opacity = 0.4 + (sin(phase) + 1) * 0.3;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.warning.withAlpha((opacity * 255).round()),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.warning.withAlpha((opacity * 0.4 * 255).round()),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }

  /// Waveform bars — speaking state
  Widget _buildSpeakingWaves() {
    return SizedBox(
      height: 60,
      child: AnimatedBuilder(
        animation: waveController,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(11, (i) {
              final phase = (waveController.value * 2 * pi) + (i * 0.6);
              final height = 14.0 + (sin(phase) * 20).abs();
              return AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 4,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.success,
                      AppColors.success.withAlpha(128),
                    ],
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  /// Idle orb — subtle waiting state
  Widget _buildIdleOrb(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, _) {
        final glow = (pulseAnimation.value - 1.0) / 0.2; // 0..1
        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(
              context,
            ).colorScheme.primary.withAlpha(((0.06 + glow * 0.04) * 255).round()),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withAlpha(((0.2 + glow * 0.1) * 255).round()),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withAlpha((glow * 0.15 * 255).round()),
                blurRadius: 12,
              ),
            ],
          ),
          child: Icon(
            Icons.mic_none_rounded,
            color: Theme.of(context).colorScheme.primary.withAlpha(178),
            size: 26,
          ),
        );
      },
    );
  }
}
