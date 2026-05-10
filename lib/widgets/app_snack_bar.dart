import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_tokens.dart';

enum AppSnackTone { neutral, info, success, warning, danger }

/// Uniform snackbar helper used across the app. Replaces ad-hoc
/// [ScaffoldMessenger]/[SnackBar] usage with consistent styling.
class AppSnackBar {
  static void show(
    BuildContext context, {
    required String message,
    AppSnackTone tone = AppSnackTone.neutral,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final color = _toneColor(context, tone);
    final ic = icon ?? _defaultIcon(tone);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          duration: duration,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(12),
          content: Row(
            children: [
              if (ic != null) ...[
                Icon(ic, color: Colors.white, size: 20),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          action: action,
        ),
      );
  }

  static void info(BuildContext c, String m) =>
      show(c, message: m, tone: AppSnackTone.info);
  static void success(BuildContext c, String m) =>
      show(c, message: m, tone: AppSnackTone.success);
  static void warning(BuildContext c, String m) =>
      show(c, message: m, tone: AppSnackTone.warning);
  static void error(BuildContext c, String m) =>
      show(c, message: m, tone: AppSnackTone.danger);

  static Color _toneColor(BuildContext context, AppSnackTone tone) {
    final cs = Theme.of(context).colorScheme;
    switch (tone) {
      case AppSnackTone.info:
        return cs.primary;
      case AppSnackTone.success:
        return AppColors.success;
      case AppSnackTone.warning:
        return AppColors.warning;
      case AppSnackTone.danger:
        return AppColors.error;
      case AppSnackTone.neutral:
        return AppColors.slate800;
    }
  }

  static IconData? _defaultIcon(AppSnackTone tone) {
    switch (tone) {
      case AppSnackTone.info:
        return Icons.info_outline_rounded;
      case AppSnackTone.success:
        return Icons.check_circle_outline_rounded;
      case AppSnackTone.warning:
        return Icons.warning_amber_rounded;
      case AppSnackTone.danger:
        return Icons.error_outline_rounded;
      case AppSnackTone.neutral:
        return null;
    }
  }
}
