// lib/services/insights_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Encapsulates all Supabase DB access for the Insights screen.
///
/// Tables touched:
///   - events        (select, update, delete)
///   - highlights    (select, update, delete)
///   - notifications (select, update, delete)
class InsightsService {
  InsightsService._internal();
  static final InsightsService instance = InsightsService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  // ── Fetch (all three tables in parallel) ──────────────────────────────────

  /// Fetches the 50 most-recent events for [userId].
  Future<List<Map<String, dynamic>>> fetchEvents(String userId) async {
    final res = await _client
        .from('events')
        .select('id, title, due_text, description, session_id, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Fetches the 50 most-recent highlights for [userId].
  Future<List<Map<String, dynamic>>> fetchHighlights(String userId) async {
    final res = await _client
        .from('highlights')
        .select('id, title, body, highlight_type, session_id, is_resolved, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Fetches the 50 most-recent notifications for [userId].
  Future<List<Map<String, dynamic>>> fetchNotifications(String userId) async {
    final res = await _client
        .from('notifications')
        .select('id, title, body, notif_type, is_read, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(res as List);
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  /// Deletes a single row by [id] from [table].
  ///
  /// [table] must be one of: 'events', 'highlights', 'notifications'.
  Future<void> deleteItem(String table, String id) async {
    assert(
      const {'events', 'highlights', 'notifications'}.contains(table),
      'deleteItem: invalid table "$table". Must be events, highlights, or notifications.',
    );
    await _client.from(table).delete().eq('id', id);
  }

  // ── Update: events ────────────────────────────────────────────────────────

  /// Updates an event's editable fields.
  ///
  /// Pass [dueText] as `null` to clear the field.
  /// Pass [description] as `null` to clear the field.
  Future<void> updateEvent({
    required String id,
    required String title,
    String? dueText,
    String? description,
  }) async {
    await _client.from('events').update({
      'title': title,
      'due_text': dueText,
      'description': description,
    }).eq('id', id);
  }

  // ── Update: highlights ────────────────────────────────────────────────────

  /// Updates a highlight's editable fields.
  Future<void> updateHighlight({
    required String id,
    required String title,
    required String body,
    required String highlightType,
  }) async {
    await _client.from('highlights').update({
      'title': title,
      'body': body,
      'highlight_type': highlightType,
    }).eq('id', id);
  }

  // ── Update: notifications ─────────────────────────────────────────────────

  /// Toggles the `is_read` flag on a notification.
  Future<void> updateNotificationReadStatus({
    required String id,
    required bool isRead,
  }) async {
    await _client
        .from('notifications')
        .update({'is_read': isRead})
        .eq('id', id);
  }
}
