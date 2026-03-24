import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/task_event_models.dart';

class TaskEventService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<EventItem>> getEvents(String userId) async {
    try {
      final response = await _supabase
          .from('events')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (response as List).map((json) => EventItem.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching events: $e');
      return [];
    }
  }

  Future<void> addEvent(EventItem event) async {
    try {
      await _supabase.from('events').insert(event.toJson());
    } catch (e) {
      print('Error adding event: $e');
      rethrow;
    }
  }

  Future<List<AppNotification>> getNotifications(String userId) async {
    try {
      final response = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => AppNotification.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching notifications: $e');
      return [];
    }
  }
}
