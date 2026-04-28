import 'package:flutter/material.dart';

/// Data model representing a unified insight item (event, highlight, or notification).
class InsightItem {
  final String id;
  final String table; // 'events' | 'highlights' | 'notifications'
  final String title;
  final String body;
  final String badge;
  final Color color;
  final IconData icon;
  final String createdAt;
  final bool isDimmed;
  final String? sessionId;

  const InsightItem({
    required this.id,
    required this.table,
    required this.title,
    required this.body,
    required this.badge,
    required this.color,
    required this.icon,
    required this.createdAt,
    this.isDimmed = false,
    this.sessionId,
  });

  factory InsightItem.fromEvent(Map<String, dynamic> ev) => InsightItem(
        id: ev['id'] as String? ?? '',
        table: 'events',
        title: ev['title'] as String? ?? 'Event',
        body: ev['description'] as String? ?? '',
        badge: ev['due_text'] as String? ?? 'Event',
        color: const Color(0xFFF59E0B),
        icon: Icons.event_rounded,
        createdAt: ev['created_at'] as String? ?? '',
        sessionId: ev['session_id'] as String?,
      );

  factory InsightItem.fromHighlight(Map<String, dynamic> hl) {
    final type = (hl['highlight_type'] as String? ?? '').toLowerCase();
    return InsightItem(
      id: hl['id'] as String? ?? '',
      table: 'highlights',
      title: hl['title'] as String? ?? 'Highlight',
      body: hl['body'] as String? ?? '',
      badge: badgeForType(type),
      color: colorForType(type),
      icon: iconForType(type),
      createdAt: hl['created_at'] as String? ?? '',
      isDimmed: hl['is_resolved'] == true,
      sessionId: hl['session_id'] as String?,
    );
  }

  factory InsightItem.fromNotification(Map<String, dynamic> nt) => InsightItem(
        id: nt['id'] as String? ?? '',
        table: 'notifications',
        title: nt['title'] as String? ?? 'Update',
        body: nt['body'] as String? ?? '',
        badge: 'Update',
        color: const Color(0xFF6366F1),
        icon: Icons.notifications_active_outlined,
        createdAt: nt['created_at'] as String? ?? '',
        isDimmed: nt['is_read'] == true,
        sessionId: null, // Notifications don't have session_id in schema
      );

  static Color colorForType(String t) {
    switch (t) {
      case 'key_fact':    return const Color(0xFF6366F1);
      case 'action_item': return const Color(0xFF10B981);
      case 'risk':        return const Color(0xFFEF4444);
      case 'opportunity': return const Color(0xFFF59E0B);
      case 'conflict':    return const Color(0xFFEC4899);
      default:            return const Color(0xFF64748B);
    }
  }

  static IconData iconForType(String t) {
    switch (t) {
      case 'key_fact':    return Icons.lightbulb_outline_rounded;
      case 'action_item': return Icons.check_circle_outline_rounded;
      case 'risk':        return Icons.warning_amber_rounded;
      case 'opportunity': return Icons.trending_up_rounded;
      case 'conflict':    return Icons.report_gmailerrorred_outlined;
      default:            return Icons.bookmark_outline_rounded;
    }
  }

  static String badgeForType(String t) {
    switch (t) {
      case 'key_fact':    return 'Key Fact';
      case 'action_item': return 'Action Item';
      case 'risk':        return 'Risk';
      case 'opportunity': return 'Opportunity';
      case 'conflict':    return 'Conflict';
      default:
        return t.isEmpty
            ? 'Note'
            : t[0].toUpperCase() + t.substring(1).replaceAll('_', ' ');
    }
  }
}
