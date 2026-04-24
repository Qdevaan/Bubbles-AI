import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_tokens.dart';

class NotificationCard extends StatelessWidget {
  final Color accentColor;
  final IconData icon;
  final String title;
  final String body;
  final String badge;
  final String? createdAt;
  final bool isDark;

  const NotificationCard({
    super.key,
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.body,
    required this.badge,
    required this.isDark,
    this.createdAt,
  });

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.glassWhite : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border(left: BorderSide(color: accentColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 15, color: accentColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(title,
                  style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.slate900)),
            ),
            Text(_formatTime(createdAt),
                style: GoogleFonts.manrope(fontSize: 11,
                    color: isDark ? AppColors.slate500 : Colors.grey.shade400)),
          ]),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(body, maxLines: 3, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(fontSize: 13,
                    color: isDark ? AppColors.slate400 : AppColors.slate500, height: 1.4)),
          ],
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accentColor.withAlpha(31),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(badge,
                style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: accentColor)),
          ),
        ],
      ),
    );
  }
}
