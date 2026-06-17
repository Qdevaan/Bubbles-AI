// Purpose: Reusable modal bottom sheet wrapper with drag handle, title row, and consistent padding.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_tokens.dart';
import 'app_dialog.dart';
import 'glass_morphism.dart';

/// Uniform modal bottom sheet used across the app. Wraps [GlassBottomSheet]
/// with a consistent drag handle, optional header (icon + title + subtitle),
/// and keyboard-aware padding. Use [AppSheet.show] to present.
class AppSheet {
  /// Generic content sheet.
  ///
  /// [child] is the body. Provide [title] / [subtitle] / [icon] to render a
  /// shared header above the body. Use [heightFactor] (0.0–1.0) to cap the
  /// sheet height as a fraction of the screen — useful for tall scrollable
  /// content.
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    String? subtitle,
    IconData? icon,
    AppDialogTone tone = AppDialogTone.neutral,
    bool isScrollControlled = true,
    bool showDragHandle = true,
    double? heightFactor,
    EdgeInsets padding = const EdgeInsets.fromLTRB(20, 8, 20, 20),
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      builder: (_) => _AppSheetShell(
        title: title,
        subtitle: subtitle,
        icon: icon,
        tone: tone,
        showDragHandle: showDragHandle,
        heightFactor: heightFactor,
        padding: padding,
        child: child,
      ),
    );
  }
}

class _AppSheetShell extends StatelessWidget {
  final Widget child;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final AppDialogTone tone;
  final bool showDragHandle;
  final double? heightFactor;
  final EdgeInsets padding;

  const _AppSheetShell({
    required this.child,
    required this.tone,
    required this.showDragHandle,
    required this.padding,
    this.title,
    this.subtitle,
    this.icon,
    this.heightFactor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = appDialogToneColor(context, tone);
    final mq = MediaQuery.of(context);
    final hasHeader = title != null || subtitle != null || icon != null;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDragHandle)
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.glassBorder : AppColors.slate300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        if (hasHeader) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withAlpha(64)),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: isDark ? Colors.white : AppColors.slate900,
                        ),
                      ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          height: 1.5,
                          color: isDark ? Colors.white70 : AppColors.slate600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Flexible(child: child),
      ],
    );

    final wrapped = Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: GlassBottomSheet(
        padding: padding,
        child: body,
      ),
    );

    if (heightFactor != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: mq.size.height * heightFactor!,
        ),
        child: wrapped,
      );
    }
    return wrapped;
  }
}
