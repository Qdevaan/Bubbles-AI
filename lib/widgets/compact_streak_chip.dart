import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/design_tokens.dart';

class CompactStreakChip extends StatelessWidget {
  final int streak;
  final int xp;
  final VoidCallback? onTap;

  const CompactStreakChip({
    super.key,
    required this.streak,
    required this.xp,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? AppColors.glassWhite : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🔥$streak',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '⚡$xp',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

