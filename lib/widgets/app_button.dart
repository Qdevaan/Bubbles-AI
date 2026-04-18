import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/design_tokens.dart';

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool loading;
  final bool filled;
  final IconData? icon;

  const AppButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.filled = true,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!filled) {
      // Outline / glass-pill style
      return Semantics(
        button: true,
        label: label,
        enabled: !loading,
        child: GestureDetector(
          onTap: loading ? null : () { HapticFeedback.lightImpact(); onTap(); },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.glassWhite : Colors.white.withAlpha(180),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: isDark ? AppColors.glassBorder : Colors.grey.shade300,
                  ),
                ),
                child: Center(
                  child: loading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: isDark ? Colors.white : AppColors.slate700,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              label,
                              style: GoogleFonts.manrope(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.slate200 : AppColors.slate700,
                              ),
                            ),
                            if (icon != null) ...[
                              const SizedBox(width: 8),
                              Icon(icon, size: 18, color: isDark ? AppColors.slate200 : AppColors.slate700),
                            ],
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Filled — gradient primary with glow
    return Semantics(
      button: true,
      label: label,
      enabled: !loading,
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withAlpha(200)],
            ),
            borderRadius: BorderRadius.circular(AppRadius.full),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withAlpha(51),
                blurRadius: 16,
                offset: const Offset(0, 4),
                spreadRadius: -2,
              ),
            ],
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (icon != null) ...[
                        const SizedBox(width: 8),
                        Icon(icon, size: 18, color: Colors.white),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
