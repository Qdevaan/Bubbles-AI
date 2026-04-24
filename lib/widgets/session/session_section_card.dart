import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_tokens.dart';

/// A styled card used to display structured advice sections (ADVICE,
/// CLARIFICATION, CONFIRMATION) in the active session HUD.
class SessionSectionCard extends StatelessWidget {
  final String title;
  final String content;
  final Color bg;
  final Color fg;
  final IconData icon;
  final bool isDark;

  const SessionSectionCard({
    super.key,
    required this.title,
    required this.content,
    required this.bg,
    required this.fg,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                title,
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: fg,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            content,
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: isDark ? AppColors.slate200 : AppColors.slate700,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
