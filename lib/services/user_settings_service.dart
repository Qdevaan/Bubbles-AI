import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralised data-access layer for the `user_settings` table.
///
/// All reads and writes for per-user preferences that need to be
/// persisted server-side go through this singleton so that no other
/// service imports `supabase_flutter` just for DB calls.
class UserSettingsService {
  UserSettingsService._internal();
  static final UserSettingsService instance = UserSettingsService._internal();

  final _client = Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // READ
  // ---------------------------------------------------------------------------

  /// Fetches the settings row for [userId] from `user_settings`.
  /// Returns `null` when no row exists yet (first-time user).
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

  /// Inserts or updates the settings row for [userId].
  ///
  /// [payload] must NOT include `user_id` — it is injected automatically.
  /// Only the keys present in [payload] are changed; other columns are
  /// left untouched thanks to the `upsert` merge behaviour.
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

  /// Updates a single column for [userId].
  Future<void> setSetting(String userId, String key, dynamic value) =>
      upsertSettings(userId, {key: value});
}
