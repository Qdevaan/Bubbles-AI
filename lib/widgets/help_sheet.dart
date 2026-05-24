import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/help_content.dart';
import '../theme/design_tokens.dart';

/// Compact AppBar action that opens a [HelpSheet] for the given screen.
class HelpIconButton extends StatelessWidget {
  final HelpScreen screen;
  final Color? color;

  const HelpIconButton({super.key, required this.screen, this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor =
        color ?? (isDark ? Colors.white : AppColors.slate900);
    return IconButton(
      tooltip: 'Help & tips',
      icon: Icon(Icons.help_outline_rounded, color: iconColor),
      onPressed: () => HelpSheet.show(context, screen),
    );
  }
}

/// Modal bottom sheet rendering a [HelpEntry] for a given [HelpScreen].
class HelpSheet extends StatelessWidget {
  final HelpScreen screen;

  const HelpSheet({super.key, required this.screen});

  static Future<void> show(BuildContext context, HelpScreen screen) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HelpSheet(screen: screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = HelpContent.get(screen);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final maxHeight = mq.size.height * 0.85;

    final bg = isDark ? AppColors.surfaceDark : Colors.white;
    final fg = isDark ? Colors.white : AppColors.slate900;
    final muted = isDark ? AppColors.slate300 : AppColors.slate600;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.xxl),
          ),
          border: Border.all(
            color: isDark
                ? AppColors.surfaceDarkHighlight
                : AppColors.slate200,
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.slate600
                      : AppColors.slate300,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.glassPrimary,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: AppColors.glassPrimaryBorder,
                        width: 0.5,
                      ),
                    ),
                    child: Icon(
                      entry.icon,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: GoogleFonts.manrope(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: fg,
                          ),
                        ),
                        if (entry.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            entry.subtitle,
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: muted),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  24 + mq.viewInsets.bottom,
                ),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.overview,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: muted,
                      ),
                    ),
                    if (entry.sections.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'What this screen does',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...entry.sections.map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SectionTile(
                            section: s,
                            isDark: isDark,
                            fg: fg,
                            muted: muted,
                          ),
                        ),
                      ),
                    ],
                    if (entry.tips.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Pro tips',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.amber,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...entry.tips.map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 3),
                                child: Icon(
                                  Icons.bolt_rounded,
                                  size: 16,
                                  color: AppColors.amber,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  t,
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    height: 1.45,
                                    color: muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final HelpSection section;
  final bool isDark;
  final Color fg;
  final Color muted;

  const _SectionTile({
    required this.section,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceDarkHighlight.withAlpha(140)
            : AppColors.slate50,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark
              ? AppColors.surfaceDarkHighlight
              : AppColors.slate200,
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(section.icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  section.body,
                  style: GoogleFonts.manrope(
                    fontSize: 13.5,
                    height: 1.45,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
