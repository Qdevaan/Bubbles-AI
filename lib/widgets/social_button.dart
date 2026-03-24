import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/design_tokens.dart';

class SocialButton extends StatelessWidget {
  final String label;
  final String? imagePath;
  final IconData? icon;
  final VoidCallback onTap;
  final bool loading;

  const SocialButton({
    super.key,
    required this.label,
    this.imagePath,
    this.icon,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: label,
      enabled: !loading,
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: isDark ? AppColors.glassWhite : Colors.white.withAlpha(200),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading)
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: isDark ? Colors.white : AppColors.slate700,
                      ),
                    )
                  else ...[
                    if (imagePath != null)
                      Image.asset(imagePath!, height: 22, width: 22)
                    else if (icon != null)
                      Icon(icon, size: 22, color: isDark ? Colors.white : Colors.black87),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.slate200 : AppColors.slate600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
