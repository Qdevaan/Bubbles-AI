import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import '../models/session_models.dart';

class SessionDataService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Session>> getSessions(String userId) async {
    try {
      final response = await _supabase
          .from('sessions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (response as List).map((json) => Session.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching sessions: $e');
      return [];
    }
  }

  Future<void> createSession(Session session) async {
    try {
      await _supabase.from('sessions').insert(session.toJson());
    } catch (e) {
      print('Error creating session: $e');
      rethrow;
    }
  }

  Future<List<SessionLog>> getSessionLogs(String sessionId) async {
    try {
      final response = await _supabase
          .from('session_logs')
          .select()
          .eq('session_id', sessionId)
          .order('turn_index', ascending: true);

      return (response as List).map((json) => SessionLog.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching session logs: $e');
      return [];
    }
  }

  Future<void> logSessionTurn(SessionLog log) async {
    try {
      await _supabase.from('session_logs').insert(log.toJson());
    } catch (e) {
      print('Error logging session turn: $e');
      rethrow;
    }
  }
}
