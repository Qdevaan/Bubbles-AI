import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../routes/app_router.dart';
import '../services/voice_assistant_service.dart';
import '../theme/design_tokens.dart';
import 'glass_morphism.dart';
import 'voice/voice_overlay_controls.dart';
import 'voice/voice_visual_indicator.dart';

/// A global voice assistant overlay that matches the Bubbles design system.
/// Triggered by the "Hey Bubbles" wake word Ã¢â‚¬â€ slides up from the bottom
/// with a glassmorphic panel showing state, waveforms, and response text.
class VoiceOverlay extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;

  const VoiceOverlay({super.key, this.navigatorKey});

  @override
  State<VoiceOverlay> createState() => _VoiceOverlayState();
}

class _VoiceOverlayState extends State<VoiceOverlay>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VoiceAssistantService>(
      builder: (context, assistant, _) {
        // Don't show on auth screens
        if (!assistant.isActive) return const SizedBox.shrink();

        // Handle pending navigation
        final nav = assistant.consumePendingNavigation();
        if (nav != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            AppRouter.router.push(
              nav['route'] as String,
              extra: nav['args'],
            );
          });
        }

        // Only render when overlay is visible
        if (!assistant.isOverlayVisible) return const SizedBox.shrink();

        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Stack(
          children: [
            // Ã¢â€â‚¬Ã¢â€â‚¬ Scrim Ã¢â€â‚¬Ã¢â€â‚¬
            Positioned.fill(
              child: Semantics(
                label: 'Dismiss voice assistant',
                button: true,
                child: GestureDetector(
                onTap: () => assistant.hideOverlay(),
                child: AnimatedContainer(
                  duration: AppDurations.normal,
                  color: (isDark ? AppColors.backgroundDark : Colors.black)
                      .withAlpha(153),
                ),
              ),
              ),
            ),

            // Ã¢â€â‚¬Ã¢â€â‚¬ Panel Ã¢â€â‚¬Ã¢â€â‚¬
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildPanel(context, assistant, isDark),
            ),
          ],
        );
      },
    );
  }

  // Ã¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€Â
  // PANEL
  // Ã¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€ÂÃ¢â€Â

  Widget _buildPanel(
    BuildContext context,
    VoiceAssistantService assistant,
    bool isDark,
  ) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          borderRadius: AppRadius.xxl,
          borderColor: Theme.of(context).colorScheme.primary.withAlpha(isDark ? 80 : 40),
          backgroundColor: isDark 
              ? AppColors.backgroundDark.withAlpha(200) 
              : Theme.of(context).colorScheme.primary.withAlpha(20), // Accent tint
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VoiceStatusChip(
                state: assistant.state,
                pulseAnimation: _pulseAnimation,
                isDark: isDark,
              ),
              const SizedBox(height: 24),
              VoiceVisualIndicator(
                state: assistant.state,
                pulseAnimation: _pulseAnimation,
                waveController: _waveController,
                isDark: isDark,
              ),
              const SizedBox(height: 24),
              VoiceTextDisplay(assistant: assistant, isDark: isDark),
              const SizedBox(height: 20),
              VoiceBottomBar(assistant: assistant, isDark: isDark),
            ],
          ),
        ),
      ),
    );
  }
}
