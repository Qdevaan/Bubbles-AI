// Purpose: Singleton wrapper for user_settings table reads/writes — keeps supabase_flutter out of other services.
import 'package:supabase_flutter/supabase_flutter.dart';

// Singleton wrapper for user_settings table reads/writes.
// Keeps supabase_flutter imports out of other services.
class UserSettingsService {
  UserSettingsService._internal();
  static final UserSettingsService instance = UserSettingsService._internal();

  final _client = Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // READ
  // ---------------------------------------------------------------------------

  // Returns null when no row exists yet (first-time user)
  Future<Map<String, dynamic>?> fetchSettings(String userId) async {
    final data = await _client
        .from('user_settings')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return data;
  }

  // ---------------------------------------------------------------------------
  // WRITE
  // ---------------------------------------------------------------------------

  // [payload] must NOT include user_id — injected automatically
  // Only keys present in payload are changed (upsert merge behaviour)
  Future<void> upsertSettings(
    String userId,
    Map<String, dynamic> payload,
  ) async {
    await _client
        .from('user_settings')
        .upsert({'user_id': userId, ...payload});
  }

  // ---------------------------------------------------------------------------
  // CONVENIENCE HELPERS
  // ---------------------------------------------------------------------------

  Future<void> setSetting(String userId, String key, dynamic value) =>
      upsertSettings(userId, {key: value});
}
