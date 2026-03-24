import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design-system colors matching the Stitch glassmorphism UI mockups.
/// Based on Tailwind CSS Slate palette + brand colors.
class AppColors {
  // Primary — Cyan accent from Stitch
  static const Color primary = Color(0xFF13BDEC);
  static const Color primaryDark = Color(0xFF0B9AC9);
  static const Color primaryLight = Color(0xFF6ECBF5);
  static const Color primaryGlow = Color(0xFF00D2FF);

  // Backgrounds — dark mesh gradient base
  static const Color backgroundDark = Color(0xFF101E22);
  static const Color backgroundLight = Color(0xFFF6F8F8);

  // Surfaces (glass cards / panels)
  static const Color surfaceDark = Color(0xFF192B33);
  static const Color surfaceDarkHighlight = Color(0xFF233C48);
  static const Color surfaceLight = Color(0xFFFFFFFF);

  // Glass colors
  static const Color glassWhite = Color(0x08FFFFFF); // rgba(255,255,255,0.03)
  static const Color glassBorder = Color(0x1AFFFFFF); // rgba(255,255,255,0.1)
  static const Color glassBorderLight = Color(0x0DFFFFFF); // rgba(255,255,255,0.05)
  static const Color glassInput = Color(0x0DFFFFFF); // rgba(255,255,255,0.05)
  static const Color glassPrimary = Color(0x2613BDEC); // rgba(19,189,236,0.15)
  static const Color glassPrimaryBorder = Color(0x4D13BDEC); // rgba(19,189,236,0.3)

  // Chat bubbles
  static const Color bubbleDark = Color(0xFF1C2A33);
  static const Color bubbleUser = Color(0x1A13BDEC); // 10% primary
  static const Color bubbleUserBorder = Color(0x3313BDEC); // 20% primary

  // Tailwind Slate scale
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate900 = Color(0xFF0F172A);

  // Text (aliased from slate)
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = slate400;
  static const Color textMuted = slate500;

  // Accents
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color accent = Color(0xFF818CF8); // indigo-400
  static const Color orange = Color(0xFFF97316);
  static const Color purple = Color(0xFFA855F7);
  static const Color amber = Color(0xFFF59E0B);
}

class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double full = 9999;
}

class AppSpacing {
  static const double xs = 6;
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double xl = 32;
}

class AppDurations {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration pulse = Duration(milliseconds: 1500);
  static const Duration dialog = Duration(milliseconds: 300);
  static const Duration tooltip = Duration(milliseconds: 200);
  static const Duration pageTransition = Duration(milliseconds: 350);
}

class AppTypography {
  static TextStyle hero(BuildContext context) => GoogleFonts.manrope(
    fontSize: 36,
    fontWeight: FontWeight.w200,
    color: Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : AppColors.slate900,
  );

  static TextStyle title(BuildContext context) => GoogleFonts.manrope(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : AppColors.slate900,
  );

  static TextStyle subtitle(BuildContext context) => GoogleFonts.manrope(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : AppColors.slate900,
  );

  static TextStyle label(BuildContext context) => GoogleFonts.manrope(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    color: Theme.of(context).brightness == Brightness.dark
        ? AppColors.slate400
        : AppColors.slate500,
  );

  static TextStyle body(BuildContext context) => GoogleFonts.manrope(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: Theme.of(context).brightness == Brightness.dark
        ? AppColors.slate300
        : AppColors.slate600,
  );

  static TextStyle caption(BuildContext context) => GoogleFonts.manrope(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: Theme.of(context).brightness == Brightness.dark
        ? AppColors.slate500
        : AppColors.slate400,
  );
}
