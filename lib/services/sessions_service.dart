// Purpose: Supabase DB access for live and consultant sessions — stream, fetch, delete, and fetch logs.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionsService {
  SessionsService._internal();
  static final SessionsService instance = SessionsService._internal();

  final _client = Supabase.instance.client;

  // Sessions table

  // Real-time stream of live_wingman sessions for a user, newest first
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

  Future<List<Map<String, dynamic>>> fetchLiveSessions(String userId) async {
    final stopwatch = Stopwatch()..start();
    try {
      final data = await _client
          .from('sessions')
          .select('id, user_id, title, session_type, mode, status, created_at, end_time, ended_at')
          .eq('user_id', userId)
          .or('mode.eq.live_wingman,session_type.eq.live_wingman')
          .order('created_at', ascending: false)
          .limit(50);
      debugPrint('⏱️ fetchLiveSessions took ${stopwatch.elapsedMilliseconds}ms');
      return List<Map<String, dynamic>>.from(data as List);
    } catch (e) {
      debugPrint('❌ fetchLiveSessions error after ${stopwatch.elapsedMilliseconds}ms: $e');
      rethrow;
    }
  }

  // One-time fetch of consultant sessions, newest first (max 50)
  Future<List<Map<String, dynamic>>> fetchConsultantSessions(
      String userId) async {
    final stopwatch = Stopwatch()..start();
    try {
      final data = await _client
          .from('sessions')
          .select('id, user_id, title, session_type, mode, status, created_at, end_time, ended_at')
          .eq('user_id', userId)
          .or('mode.eq.consultant,session_type.eq.consultant')
          .order('created_at', ascending: false)
          .limit(50);
      debugPrint('⏱️ fetchConsultantSessions took ${stopwatch.elapsedMilliseconds}ms');
      return List<Map<String, dynamic>>.from(data as List);
    } catch (e) {
      debugPrint('❌ fetchConsultantSessions error after ${stopwatch.elapsedMilliseconds}ms: $e');
      rethrow;
    }
  }

  Future<void> deleteSession(String sessionId) async {
    await _client.from('sessions').delete().eq('id', sessionId);
  }

  // Recent sessions across all modes, used by the conversation-mission picker
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

  // Log tables

  // Fetches all log rows for a session from either consultant_logs or session_logs
  Future<List<Map<String, dynamic>>> fetchSessionLogs({
    required String sessionId,
    required bool isConsultant,
  }) async {
    final table = isConsultant ? 'consultant_logs' : 'session_logs';
    final data = await _client
        .from(table)
        .select(isConsultant
            ? 'id, user_id, session_id, query, question, response, answer, source_screen, created_at'
            : 'id, session_id, turn_index, role, content, created_at, speaker_label')
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(data as List);
  }
}
