import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_tokens.dart';
import 'insight_item.dart';
import 'insight_chips.dart';

// ── Insight Tile ──────────────────────────────────────────────────────────────

class InsightTile extends StatefulWidget {
  final InsightItem item;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const InsightTile({
    super.key,
    required this.item,
    required this.isDark,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<InsightTile> createState() => _InsightTileState();
}

class _InsightTileState extends State<InsightTile>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _ctrl;
  late Animation<double> _expandAnim;
  late Animation<double> _chevronTurn;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _chevronTurn = Tween<double>(begin: 0.0, end: 0.5).animate(_expandAnim);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isDark = widget.isDark;
    final hasBody = item.body.isNotEmpty;
    final timeStr = _formatTime(item.createdAt);

    return Dismissible(
      key: ValueKey('dismiss_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error.withAlpha(200),
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.white, size: 24),
      ),
      confirmDismiss: (_) async {
        widget.onDelete();
        return false;
      },
      child: GestureDetector(
        onTap: hasBody ? _toggle : null,
        onLongPress: () => _showActions(context),
        child: Opacity(
          opacity: item.isDimmed ? 0.55 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: isDark ? AppColors.glassWhite : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.xxl),
              border: Border(left: BorderSide(color: item.color, width: 3)),
              boxShadow: _expanded
                  ? [
                      BoxShadow(
                        color: item.color.withAlpha(isDark ? 30 : 15),
                        blurRadius: 16,
                        spreadRadius: -2,
                      ),
                    ]
                  : isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withAlpha(10),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: item.color.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(item.icon, size: 14, color: item.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title,
                              style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.slate900)),
                          if (timeStr.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(timeStr,
                                  style: GoogleFonts.manrope(
                                      fontSize: 11,
                                      color: isDark
                                          ? AppColors.slate500
                                          : Colors.grey.shade400)),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: item.color.withAlpha(25),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(color: item.color.withAlpha(80)),
                      ),
                      child: Text(item.badge,
                          style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: item.color)),
                    ),
                    if (hasBody) ...[
                      const SizedBox(width: 4),
                      RotationTransition(
                        turns: _chevronTurn,
                        child: Icon(Icons.expand_more_rounded,
                            size: 20,
                            color: isDark
                                ? AppColors.slate500
                                : Colors.grey.shade400),
                      ),
                    ] else ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _showActions(context),
                        child: Icon(Icons.more_vert_rounded,
                            size: 18,
                            color: isDark
                                ? AppColors.slate500
                                : Colors.grey.shade400),
                      ),
                    ],
                  ]),

                  // Preview (collapsed: 1 line)
                  if (hasBody && !_expanded)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(item.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                              fontSize: 13,
                              height: 1.4,
                              color: isDark
                                  ? AppColors.slate400
                                  : AppColors.slate500)),
                    ),

                  // Expanded body
                  SizeTransition(
                    sizeFactor: _expandAnim,
                    axisAlignment: -1.0,
                    child: hasBody
                        ? Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Full body in styled container
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withAlpha(5)
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark
                                          ? AppColors.glassBorder
                                          : Colors.grey.shade100,
                                    ),
                                  ),
                                  child: Text(item.body,
                                      style: GoogleFonts.manrope(
                                          fontSize: 13,
                                          color: isDark
                                              ? AppColors.slate300
                                              : AppColors.slate600,
                                          height: 1.6)),
                                ),
                                const SizedBox(height: 10),
                                // Action buttons row
                                Row(
                                  children: [
                                    InsightActionChip(
                                      icon: item.table == 'notifications'
                                          ? Icons.mark_email_read_outlined
                                          : Icons.edit_outlined,
                                      label: item.table == 'notifications'
                                          ? (item.isDimmed
                                              ? 'Mark unread'
                                              : 'Mark read')
                                          : 'Edit',
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      isDark: isDark,
                                      onTap: widget.onEdit,
                                    ),
                                    const SizedBox(width: 8),
                                    InsightActionChip(
                                      icon: Icons.delete_outline_rounded,
                                      label: 'Delete',
                                      color: AppColors.error,
                                      isDark: isDark,
                                      onTap: widget.onDelete,
                                    ),
                                    if (item.sessionId != null &&
                                        item.sessionId!.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      InsightActionChip(
                                        icon: Icons.arrow_forward_rounded,
                                        label: 'Source',
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        isDark: isDark,
                                        onTap: () => Navigator.pushNamed(
                                            context, '/session-analytics',
                                            arguments: {
                                              'sessionId': item.sessionId,
                                              'sessionTitle': item.title,
                                              'initialTab': 2
                                            }),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(50),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: widget.item.color.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: widget.item.color.withAlpha(80)),
                ),
                child: Icon(widget.item.icon, color: widget.item.color, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.item.title,
                      style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(widget.item.badge,
                      style: GoogleFonts.manrope(fontSize: 12, color: widget.item.color)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            const Divider(),
            if (widget.item.sessionId != null && widget.item.sessionId!.isNotEmpty)
              ListTile(
                leading: Icon(Icons.analytics_outlined,
                    color: Theme.of(context).colorScheme.primary),
                title: Text('View Source',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary)),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/session-analytics',
                      arguments: {
                        'sessionId': widget.item.sessionId,
                        'sessionTitle': widget.item.title,
                        'initialTab': 2
                      });
                },
              ),
            if (widget.item.table != 'notifications')
              ListTile(
                leading: Icon(Icons.edit_outlined,
                    color: Theme.of(context).colorScheme.primary),
                title: Text('Edit',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary)),
                contentPadding: EdgeInsets.zero,
                onTap: () { Navigator.pop(context); widget.onEdit(); },
              )
            else
              ListTile(
                leading: Icon(Icons.mark_email_read_outlined,
                    color: Theme.of(context).colorScheme.primary),
                title: Text(widget.item.isDimmed ? 'Mark as unread' : 'Mark as read',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary)),
                contentPadding: EdgeInsets.zero,
                onTap: () { Navigator.pop(context); widget.onEdit(); },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              contentPadding: EdgeInsets.zero,
              onTap: () { Navigator.pop(context); widget.onDelete(); },
            ),
          ],
        ),
      ),
    );
  }
}
