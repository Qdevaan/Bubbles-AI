import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/core_identity.dart';

class IdentityService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Profile?> getProfile(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response != null) {
        return Profile.fromJson(response);
      }
      return null;
    } catch (e) {
      print('Error fetching profile: $e');
      return null;
    }
  }

  Future<void> updateProfile(Profile profile) async {
    try {
      await _supabase.from('profiles').upsert(profile.toJson());
    } catch (e) {
      print('Error updating profile: $e');
      rethrow;
    }
  }

  Future<UserSettings?> getUserSettings(String userId) async {
    try {
      final response = await _supabase
          .from('user_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response != null) {
        return UserSettings.fromJson(response);
      }
      return null;
    } catch (e) {
      print('Error fetching user settings: $e');
      return null;
    }
  }

  Future<void> updateUserSettings(UserSettings settings) async {
    try {
      await _supabase.from('user_settings').upsert(settings.toJson());
    } catch (e) {
      print('Error updating user settings: $e');
      rethrow;
    }
  }
}
