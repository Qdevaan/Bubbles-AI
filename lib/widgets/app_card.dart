import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';
import 'fade_slide_transition.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final GestureTapCallback? onTap;
  final Duration delay;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.delay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FadeSlideTransition(
      delay: delay,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.glassWhite : Colors.white.withAlpha(200),
                borderRadius: BorderRadius.circular(AppRadius.xxl),
                border: Border.all(
                  color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
                  width: 1,
                ),
              ),
              padding: padding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
