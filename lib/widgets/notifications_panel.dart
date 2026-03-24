import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';
import 'package:google_fonts/google_fonts.dart';
import 'glass_morphism.dart';

/// Extracted from HomeScreen's _showNotificationsPanel().
/// Shows a draggable bottom sheet with highlights and events.
class NotificationsPanel extends StatelessWidget {
  final List<Map<String, dynamic>> highlights;
  final List<Map<String, dynamic>> events;
  final VoidCallback onClearAll;
  final bool isDark;

  const NotificationsPanel({
    super.key,
    required this.highlights,
    required this.events,
    required this.onClearAll,
    required this.isDark,
  });

  static void show(
    BuildContext context, {
    required List<Map<String, dynamic>> highlights,
    required List<Map<String, dynamic>> events,
    required VoidCallback onClearAll,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.35,
        builder: (_, scrollController) => NotificationsPanel(
          highlights: highlights,
          events: events,
          onClearAll: onClearAll,
          isDark: isDark,
        )._buildContent(context, scrollController),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ScrollController scrollController) {
    return GlassBottomSheet(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                Text(
                  'Notifications',
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                ),
                const Spacer(),
                if (highlights.isNotEmpty || events.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      onClearAll();
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Clear all',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Content
          Expanded(
            child: (highlights.isEmpty && events.isEmpty)
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_none_rounded,
                          size: 52,
                          color: isDark ? Colors.white24 : Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No notifications yet',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            color: isDark
                                ? AppColors.slate500
                                : Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Insights from your sessions will appear here.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.slate600
                                : Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (highlights.isNotEmpty)
                        ...highlights.map(
                          (hl) => _NotificationCard(
                            isDark: isDark,
                            accentColor: AppColors.error,
                            icon: Icons.warning_amber_rounded,
                            title: hl['title'] as String? ?? 'Highlight',
                            body: hl['body'] as String? ?? '',
                            badge: hl['highlight_type'] as String? ?? 'Note',
                            createdAt: hl['created_at'] as String?,
                          ),
                        ),
                      if (events.isNotEmpty)
                        ...events.map(
                          (ev) => _NotificationCard(
                            isDark: isDark,
                            accentColor: AppColors.warning,
                            icon: Icons.event_rounded,
                            title: ev['title'] as String? ?? 'Event',
                            body: ev['description'] as String? ?? '',
                            badge: ev['due_text'] as String? ?? 'Event',
                            createdAt: ev['created_at'] as String?,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildContent(context, ScrollController());
  }
}

class _NotificationCard extends StatelessWidget {
  final Color accentColor;
  final IconData icon;
  final String title;
  final String body;
  final String badge;
  final String? createdAt;
  final bool isDark;

  const _NotificationCard({
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
        color: isDark ? AppColors.slate900 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: accentColor, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                ),
              ),
              Text(
                _formatTime(createdAt),
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.slate500
                      : Colors.grey.shade400,
                ),
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: isDark
                    ? AppColors.slate400
                    : AppColors.slate500,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accentColor.withAlpha(30),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
