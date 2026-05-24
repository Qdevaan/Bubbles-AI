import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/confidence_provider.dart';
import '../theme/design_tokens.dart';

/// Small inline meter shown during an active wingman session.
/// Reads the live [ConfidenceProvider.score] and renders a smoothed
/// 0..1 bar with a colour band (red < 0.4 ≤ amber < 0.7 ≤ green).
class ConfidenceMeter extends StatelessWidget {
  const ConfidenceMeter({super.key, this.compact = false});

  final bool compact;

  static Color colorFor(double s) {
    if (s < 0.4) return AppColors.error;
    if (s < 0.7) return AppColors.warning;
    return AppColors.success;
  }

  static String labelFor(double s) {
    if (s < 0.4) return 'Hesitant';
    if (s < 0.7) return 'Okay';
    return 'Confident';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConfidenceProvider>(
      builder: (_, p, __) => _AnimatedMeter(score: p.score, compact: compact),
    );
  }
}

class _AnimatedMeter extends StatelessWidget {
  const _AnimatedMeter({required this.score, required this.compact});
  final double score;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: score, end: score),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) {
        final color = ConfidenceMeter.colorFor(v);
        final label = ConfidenceMeter.labelFor(v);
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 6 : 10,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                color: color,
                size: compact ? 14 : 16,
              ),
              SizedBox(width: compact ? 6 : 10),
              SizedBox(
                width: compact ? 60 : 90,
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(AppRadius.full),
                  child: LinearProgressIndicator(
                    value: v,
                    minHeight: compact ? 5 : 7,
                    backgroundColor: (isDark
                            ? AppColors.slate700
                            : AppColors.slate200)
                        .withValues(alpha: 0.6),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: compact ? 10.5 : 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
