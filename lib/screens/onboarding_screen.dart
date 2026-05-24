import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../routes/app_routes.dart';
import '../services/onboarding_service.dart';
import '../theme/design_tokens.dart';

class OnboardingSlide {
  final IconData icon;
  final Color tint;
  final String title;
  final String body;
  final String? cta;
  const OnboardingSlide({
    required this.icon,
    required this.tint,
    required this.title,
    required this.body,
    this.cta,
  });
}

const List<OnboardingSlide> _slides = [
  OnboardingSlide(
    icon: Icons.waving_hand_rounded,
    tint: AppColors.primary,
    title: 'Welcome to Bubbles',
    body:
        'Your AI conversation coach. Get live suggestions, rehearse scenarios, '
        'review your mistakes, and track confidence over time.',
  ),
  OnboardingSlide(
    icon: Icons.mic_rounded,
    tint: AppColors.primaryLight,
    title: 'Live Wingman',
    body:
        'Start a session before any real conversation. Bubbles transcribes in '
        'real time, suggests replies, flags mistakes, and tracks your '
        'speaking confidence on a live meter.',
    cta: 'Where: Home → Live Wingman',
  ),
  OnboardingSlide(
    icon: Icons.theater_comedy_rounded,
    tint: AppColors.accent,
    title: 'Practice scenarios',
    body:
        'Get AI-generated roleplay scenarios tailored to your persona. Read '
        'the briefing, run it as a session, then see if you hit the goal.',
    cta: 'Where: Drawer → Practice',
  ),
  OnboardingSlide(
    icon: Icons.style_rounded,
    tint: AppColors.purple,
    title: 'Drills that stick',
    body:
        'Past mistakes become flashcards on a spaced-repetition schedule. '
        'Tap to flip, grade your recall, and watch your XP climb.',
    cta: 'Where: Drawer → Drills',
  ),
  OnboardingSlide(
    icon: Icons.insights_rounded,
    tint: AppColors.success,
    title: 'See your progress',
    body:
        'A dashboard for 30 / 90 / 365 days: streak, level, mastery, '
        'sentiment, and per-metric trends. Spot patterns, not noise.',
    cta: 'Where: Drawer → Progress',
  ),
  OnboardingSlide(
    icon: Icons.help_outline_rounded,
    tint: AppColors.amber,
    title: 'Help is everywhere',
    body:
        'Every major screen has a (?) icon in the top bar. Tap it for a '
        'screen-specific explainer with tips. Replay this tour any time '
        'from Settings → Replay tutorial.',
  ),
];

class OnboardingScreen extends StatefulWidget {
  /// When true, the screen exits via Navigator.pop instead of routing to /home.
  /// Used for replay from Settings.
  final bool isReplay;

  const OnboardingScreen({super.key, this.isReplay = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _slides.length - 1;

  Future<void> _finish() async {
    await OnboardingService.instance.markSeen();
    if (!mounted) return;
    if (widget.isReplay) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacementNamed(AppRoutes.home);
    }
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: AppDurations.normal,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final fg = isDark ? Colors.white : AppColors.slate900;
    final muted = isDark ? AppColors.slate300 : AppColors.slate600;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: skip
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (widget.isReplay)
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: fg),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  else
                    const SizedBox(width: 48),
                  TextButton(
                    onPressed: _finish,
                    child: Text(
                      _isLast ? '' : 'Skip',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Pages
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _SlideView(
                  slide: _slides[i],
                  fg: fg,
                  muted: muted,
                ),
              ),
            ),
            // Indicators
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: AppDurations.fast,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.primary
                          : (isDark
                              ? AppColors.slate600
                              : AppColors.slate300),
                      borderRadius:
                          BorderRadius.circular(AppRadius.full),
                    ),
                  );
                }),
              ),
            ),
            // CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                  child: Text(
                    _isLast ? 'Get started' : 'Next',
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final OnboardingSlide slide;
  final Color fg;
  final Color muted;

  const _SlideView({
    required this.slide,
    required this.fg,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: slide.tint.withAlpha(38),
              border: Border.all(
                color: slide.tint.withAlpha(120),
                width: 1.5,
              ),
            ),
            child: Icon(slide.icon, size: 64, color: slide.tint),
          ),
          const SizedBox(height: 36),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 15.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: muted,
            ),
          ),
          if (slide.cta != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: slide.tint.withAlpha(28),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: slide.tint.withAlpha(80),
                  width: 0.5,
                ),
              ),
              child: Text(
                slide.cta!,
                style: GoogleFonts.manrope(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: slide.tint,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
