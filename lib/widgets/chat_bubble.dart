import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/design_tokens.dart';

/// A reusable chat bubble widget used across screens:
/// LiveWingman, Consultant, and Session Detail.
class ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final String? speakerLabel;
  final Widget? contentWidget;
  final bool isHighlighted;

  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.speakerLabel,
    this.contentWidget,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isHighlighted
              ? Theme.of(context).colorScheme.primary.withAlpha(38)
              : (isUser
                  ? Colors.transparent
                  : (isDark ? AppColors.glassWhite : AppColors.slate100)),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isUser ? 18 : 4),
            topRight: Radius.circular(isUser ? 4 : 18),
            bottomLeft: const Radius.circular(18),
            bottomRight: const Radius.circular(18),
          ),
          border: isHighlighted
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary.withAlpha(128),
                  width: 1.5,
                )
              : (isUser
                  ? Border.all(
                      color: isDark ? AppColors.glassBorder : Colors.grey.shade300,
                    )
                  : (isDark ? Border.all(color: AppColors.glassBorder) : null)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser && speakerLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  speakerLabel!,
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            contentWidget ??
                Text(
                  text,
                  style: GoogleFonts.manrope(
                    color: isDark ? AppColors.slate200 : AppColors.slate900,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
