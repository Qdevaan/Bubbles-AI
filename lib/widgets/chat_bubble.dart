import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/design_tokens.dart';

class ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool isAI;
  final String? speakerLabel;
  final Widget? contentWidget;
  final bool isHighlighted;
  final bool isUncertain;
  final VoidCallback? onSwitchSpeaker;
  final void Function(bool asMe)? onAttributionChange;

  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.isAI = false,
    this.speakerLabel,
    this.contentWidget,
    this.isHighlighted = false,
    this.isUncertain = false,
    this.onSwitchSpeaker,
    this.onAttributionChange,
  });

  void _showAttributionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Who said this?',
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text('This was me', style: GoogleFonts.manrope()),
                onTap: () {
                  Navigator.pop(context);
                  onAttributionChange?.call(true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: Text('This was them', style: GoogleFonts.manrope()),
                onTap: () {
                  Navigator.pop(context);
                  onAttributionChange?.call(false);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubbleOpacity = isUncertain ? 0.6 : 1.0;

    return Opacity(
      opacity: bubbleOpacity,
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Stack(
          children: [
            GestureDetector(
              onLongPress: onSwitchSpeaker,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? Theme.of(context).colorScheme.primary.withAlpha(50)
                      : (isUser
                          ? (isDark
                              ? AppColors.glassWhite.withAlpha(20)
                              : Colors.blue.withAlpha(15))
                          : (isAI
                              ? Theme.of(context).colorScheme.primary.withAlpha(isDark ? 50 : 30)
                              : (isDark ? AppColors.glassWhite : AppColors.slate100))),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isUser ? 18 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 18),
                  ),
                  border: Border.all(
                    color: isHighlighted
                        ? Theme.of(context).colorScheme.primary
                        : (isUser
                            ? (isDark
                                ? AppColors.glassBorder
                                : Colors.blue.withAlpha(100))
                            : (isAI
                                ? Theme.of(context).colorScheme.primary.withAlpha(120)
                                : (isDark
                                    ? AppColors.glassBorder
                                    : Colors.grey.shade300))),
                    width: isHighlighted || isAI ? 1.2 : 1,
                  ),
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
            ),
            if (isUncertain)
              Positioned(
                top: 0,
                right: isUser ? null : 0,
                left: isUser ? 0 : null,
                child: GestureDetector(
                  onTap: () => _showAttributionSheet(context),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('?',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
