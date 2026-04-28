import 'package:supabase_flutter/supabase_flutter.dart';

/// Data-access layer for sessions and session-log tables.
/// All direct Supabase DB calls from sessions_screen are routed through here.
class SessionsService {
  SessionsService._internal();
  static final SessionsService instance = SessionsService._internal();

  final _client = Supabase.instance.client;

  // ── Sessions table ──────────────────────────────────────────────────────────

  /// Returns a real-time stream of all sessions for [userId] filtered to
  /// [mode] == 'live_wingman', ordered newest-first.
  Stream<List<Map<String, dynamic>>> streamLiveSessions(String userId) {
    return _client
        .from('sessions')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map(
          (data) => List<Map<String, dynamic>>.from(data)
              .where((s) => s['mode'] == 'live_wingman' || s['session_type'] == 'live_wingman')
              .toList(),
        );
  }

  /// Fetches the list of live sessions once (Future-based).
  Future<List<Map<String, dynamic>>> fetchLiveSessions(String userId) async {
    final data = await _client
        .from('sessions')
        .select('id, user_id, title, summary, session_type, mode, status, created_at, end_time, ended_at')
        .eq('user_id', userId)
        .or('mode.eq.live_wingman,session_type.eq.live_wingman')
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Returns a one-time fetch of consultant sessions for [userId],
  /// ordered newest-first (max 50 rows).
  Future<List<Map<String, dynamic>>> fetchConsultantSessions(
      String userId) async {
    final data = await _client
        .from('sessions')
        .select('id, user_id, title, summary, session_type, mode, status, created_at, end_time, ended_at')
        .eq('user_id', userId)
        .or('mode.eq.consultant,session_type.eq.consultant')
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Deletes the session row with the given [sessionId].
  Future<void> deleteSession(String sessionId) async {
    await _client.from('sessions').delete().eq('id', sessionId);
  }

  /// Returns the user's most recent sessions across all modes, optionally
  /// filtered to completed-only. Used by the conversation-mission session picker.
  Future<List<Map<String, dynamic>>> fetchRecentSessions(
    String userId, {
    int limit = 25,
    bool completedOnly = true,
  }) async {
    final query = _client
        .from('sessions')
        .select('id, title, summary, mode, status, created_at, end_time, ended_at')
        .eq('user_id', userId);

    final filtered = completedOnly ? query.eq('status', 'completed') : query;

    final data = await filtered
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(data as List);
  }

  // ── Log tables ──────────────────────────────────────────────────────────────

  /// Fetches all log rows for [sessionId] from either 'consultant_logs' or
  /// 'session_logs' depending on [isConsultant], ordered chronologically.
  Future<List<Map<String, dynamic>>> fetchSessionLogs({
    required String sessionId,
    required bool isConsultant,
  }) async {
    final table = isConsultant ? 'consultant_logs' : 'session_logs';
    final data = await _client
        .from(table)
        .select(isConsultant 
            ? 'id, user_id, session_id, query, question, response, answer, created_at'
            : 'id, session_id, turn_index, role, content, created_at, speaker_label')
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(data as List);
  }
}
