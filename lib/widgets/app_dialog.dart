// Purpose: Reusable modal dialog wrapper with consistent title, content, and action button styling.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_tokens.dart';
import 'glass_morphism.dart';

enum AppDialogTone { neutral, info, success, warning, danger }

/// Default icon for a given tone. Exposed so [AppSheet] can reuse it.
IconData appDialogToneIcon(AppDialogTone tone) {
  switch (tone) {
    case AppDialogTone.info:
      return Icons.info_outline_rounded;
    case AppDialogTone.success:
      return Icons.check_circle_outline_rounded;
    case AppDialogTone.warning:
      return Icons.warning_amber_rounded;
    case AppDialogTone.danger:
      return Icons.error_outline_rounded;
    case AppDialogTone.neutral:
      return Icons.help_outline_rounded;
  }
}

/// Resolves a tone to a color. Exposed so [AppSheet] can reuse it.
Color appDialogToneColor(BuildContext context, AppDialogTone tone) {
  final cs = Theme.of(context).colorScheme;
  switch (tone) {
    case AppDialogTone.info:
      return cs.primary;
    case AppDialogTone.success:
      return AppColors.success;
    case AppDialogTone.warning:
      return AppColors.warning;
    case AppDialogTone.danger:
      return AppColors.error;
    case AppDialogTone.neutral:
      return cs.primary;
  }
}

class AppDialogAction {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool destructive;
  final bool loading;
  const AppDialogAction({
    required this.label,
    this.onTap,
    this.primary = false,
    this.destructive = false,
    this.loading = false,
  });
}

/// Uniform dialog used across the app. Wraps [GlassDialog] with a consistent
/// header (icon + title + optional subtitle), body content and a single row of
/// actions. Use [AppDialog.show] to present.
class AppDialog extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? content;
  final List<AppDialogAction> actions;
  final AppDialogTone tone;

  const AppDialog({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.content,
    this.actions = const [],
    this.tone = AppDialogTone.neutral,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    IconData? icon,
    String? subtitle,
    Widget? content,
    List<AppDialogAction> actions = const [],
    AppDialogTone tone = AppDialogTone.neutral,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => AppDialog(
        title: title,
        icon: icon,
        subtitle: subtitle,
        content: content,
        actions: actions,
        tone: tone,
      ),
    );
  }

  /// Convenience: Yes/No confirm. Returns true if user confirmed.
  static Future<bool> confirm({
    required BuildContext context,
    required String title,
    String? message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    AppDialogTone tone = AppDialogTone.warning,
    IconData? icon,
  }) async {
    final result = await show<bool>(
      context: context,
      title: title,
      subtitle: message,
      icon: icon ?? appDialogToneIcon(tone),
      tone: tone,
      actions: [
        AppDialogAction(label: cancelLabel, onTap: () => Navigator.of(context).pop(false)),
        AppDialogAction(
          label: confirmLabel,
          primary: true,
          destructive: tone == AppDialogTone.danger,
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    return result ?? false;
  }

  /// Convenience: single-action info dialog.
  static Future<void> notice({
    required BuildContext context,
    required String title,
    String? message,
    String okLabel = 'OK',
    AppDialogTone tone = AppDialogTone.info,
    IconData? icon,
  }) {
    return show<void>(
      context: context,
      title: title,
      subtitle: message,
      icon: icon ?? appDialogToneIcon(tone),
      tone: tone,
      actions: [
        AppDialogAction(
          label: okLabel,
          primary: true,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  /// Convenience: blocking spinner dialog. Caller dismisses via
  /// `Navigator.of(context, rootNavigator: true).pop()`.
  static Future<void> loading({
    required BuildContext context,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LoadingDialog(message: message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = appDialogToneColor(context, tone);

    return GlassDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                child: Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 12),
            Text(
              subtitle!,
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.5,
                color: isDark ? Colors.white70 : AppColors.slate600,
              ),
            ),
          ],
          if (content != null) ...[
            const SizedBox(height: 16),
            content!,
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 24),
            _ActionRow(actions: actions, accent: accent, isDark: isDark),
          ],
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final List<AppDialogAction> actions;
  final Color accent;
  final bool isDark;

  const _ActionRow({required this.actions, required this.accent, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (actions.length == 1) {
      return SizedBox(
        height: 48,
        child: _buildButton(context, actions.first, expand: true),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: SizedBox(height: 48, child: _buildButton(context, actions[i]))),
        ],
      ],
    );
  }

  Widget _buildButton(BuildContext context, AppDialogAction action, {bool expand = false}) {
    final color = action.destructive ? AppColors.error : accent;
    if (action.primary) {
      return ElevatedButton(
        onPressed: action.loading ? null : action.onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: action.loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : Text(
                action.label,
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
              ),
      );
    }
    return TextButton(
      onPressed: action.loading ? null : action.onTap,
      style: TextButton.styleFrom(
        foregroundColor: action.destructive ? AppColors.error : (isDark ? Colors.white70 : AppColors.slate600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(action.label, style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
    );
  }
}

class _LoadingDialog extends StatelessWidget {
  final String message;
  const _LoadingDialog({required this.message});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassDialog(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              message,
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
