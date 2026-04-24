import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_tokens.dart';

// ── Empty / Error states ──────────────────────────────────────────────────────

class InsightsEmptyState extends StatelessWidget {
  final bool isDark;
  const InsightsEmptyState({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [primary, primary.withAlpha(80)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(bounds),
            child: Icon(Icons.auto_awesome_outlined, size: 64,
                color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text('Nothing here yet',
              style: GoogleFonts.manrope(fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.slate400 : AppColors.slate600)),
          const SizedBox(height: 8),
          Text('Start a session to generate\npersonalized insights.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 13, height: 1.5,
                  color: isDark ? AppColors.slate500 : AppColors.slate400)),
        ]),
      ),
    );
  }
}

class InsightsSearchEmptyState extends StatelessWidget {
  final bool isDark;
  final String query;
  const InsightsSearchEmptyState({super.key, required this.isDark, required this.query});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.search_off_rounded, size: 52,
                color: (isDark ? Colors.white : Colors.black).withAlpha(40)),
            const SizedBox(height: 16),
            Text('No results for "$query"',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.slate400 : AppColors.slate600)),
            const SizedBox(height: 8),
            Text('Try a different search term.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 13,
                    color: isDark ? AppColors.slate500 : AppColors.slate400)),
          ]),
        ),
      );
}

class InsightsErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final bool isDark;
  const InsightsErrorState(
      {super.key, required this.error, required this.onRetry, required this.isDark});

  String get _friendlyTitle {
    if (error == 'please_login') return 'You\'re not signed in';
    return 'Something went wrong';
  }

  String get _friendlySubtitle {
    if (error == 'please_login') {
      return 'Sign in to see your insights and highlights.';
    }
    return 'We couldn\'t load your insights right now.\nPlease check your internet and try again.';
  }

  IconData get _icon {
    if (error == 'please_login') return Icons.lock_outline_rounded;
    return Icons.cloud_off_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (isDark ? Colors.white : Colors.black).withAlpha(10),
            ),
            child: Icon(_icon,
                size: 36,
                color: isDark ? AppColors.slate400 : AppColors.slate500),
          ),
          const SizedBox(height: 16),
          Text(_friendlyTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.slate900)),
          const SizedBox(height: 8),
          Text(_friendlySubtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontSize: 13,
                  height: 1.5,
                  color: isDark ? AppColors.slate400 : AppColors.slate500)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
