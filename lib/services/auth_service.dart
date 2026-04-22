import 'dart:convert'; // Needed for JSON encoding/decoding
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import this
import 'analytics_service.dart';
import '../repositories/profile_repository.dart';
import '../cache/persistent_cache_service.dart';

class AuthService {
  // Singleton Pattern
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  ProfileRepository? _profileRepository;
  void setProfileRepository(ProfileRepository repo) => _profileRepository = repo;

  // Key for storing profile data in SharedPreferences
  static const String _profileCacheKey = 'cached_user_profile';

  /// Returns the current authenticated user, or null if not signed in.
  User? get currentUser => _client.auth.currentUser;

  /// Returns the current session, or null if expired/missing.
  Session? get currentSession => _client.auth.currentSession;

  /// Checks if the current user's email is verified based on Supabase metadata.
  bool get isEmailVerified =>
      _client.auth.currentUser?.emailConfirmedAt != null;

  /// JWT access token for the current session. Null when signed out.
  String? get accessToken => _client.auth.currentSession?.accessToken;

  /// Supabase user ID for the current session. Null when signed out.
  String? get currentUserId => _client.auth.currentUser?.id;

  // ---------------------------------------------------------------------------
  // AUTHENTICATION METHODS
  // ---------------------------------------------------------------------------

  Future<void> signInWithGoogle() async {
    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.bubbles://login-callback/',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      AnalyticsService.instance.logAction(
        action: 'user_login',
        entityType: 'auth',
        details: {'method': 'google'},
      );
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  Future<void> resendVerificationEmail(String email) async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: 'io.supabase.bubbles://login-callback/',
      );
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    try {
      await _client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: 'io.supabase.bubbles://login-callback/',
      );
      AnalyticsService.instance.logAction(
        action: 'user_signup',
        entityType: 'auth',
        details: {'method': 'email'},
      );
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
      AnalyticsService.instance.logAction(
        action: 'user_login',
        entityType: 'auth',
        details: {'method': 'email'},
      );
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  /// Sends a password reset email via Supabase.
  /// Always returns success (Supabase does not reveal whether the email exists).
  Future<void> resetPasswordForEmail(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.supabase.bubbles://reset-password',
      );
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  /// Updates the authenticated user's password (used after password reset flow).
  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  /// Sign out the current user and CLEAR local cache.
  Future<void> signOut() async {
    try {
      final userId = currentUserId;
      AnalyticsService.instance.logAction(
        action: 'user_logout',
        entityType: 'auth',
      );
      await AnalyticsService.instance.flushNow();

      // 1. Clear user-scoped cache across all layers (L1 and L2)
      if (userId != null) {
        await PersistentCacheService.instance.purgeUserScope(userId);
        if (_profileRepository != null) {
          _profileRepository!.l1.purgeUserScope(userId);
        }
      }

      // 2. Supabase sign out
      await _client.auth.signOut();

      // Clear legacy cache if repository not active
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_profileCacheKey);
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  /// Deletes the current user's account by calling the Supabase `delete_user` RPC.
  /// The caller is responsible for signing out on success.
  /// Throws on RPC failure — the account is NOT deleted if this throws.
  ///
  /// PREREQUISITE: The `delete_user` SQL function must exist in Supabase:
  /// CREATE OR REPLACE FUNCTION delete_user() RETURNS void AS $$
  ///   BEGIN DELETE FROM auth.users WHERE id = auth.uid(); END;
  /// $$ LANGUAGE plpgsql SECURITY DEFINER;
  Future<void> deleteAccount() async {
    try {
      await _client.rpc('delete_user');
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // PROFILE & DATA METHODS (Caching Implemented Here)
  // ---------------------------------------------------------------------------

  /// Fetches the user's profile.
  Future<Map<String, dynamic>?> getProfile({bool forceRefresh = false}) async {
    final user = currentUser;
    if (user == null) return null;

    if (_profileRepository != null) {
      final result = await _profileRepository!.getProfile(user.id, forceRefresh: forceRefresh);
      return result.data;
    }
    return null;
  }

  /// Inserts or updates the user's profile data AND updates local cache.
  Future<void> upsertProfile({
    String? fullName,
    String? avatarUrl,
    DateTime? dob,
    String? gender,
    String? country,
  }) async {
    try {
      final user = currentUser;
      if (user == null) throw const AuthException('User not authenticated');

      final updates = {
        'id': user.id,
        'full_name': fullName,
        'avatar_url': avatarUrl,
        'dob': dob?.toIso8601String().split('T').first,
        'gender': gender,
        'country': country,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Remove nulls so we don't wipe out existing data with nulls
      updates.removeWhere((key, value) => value == null);

      if (_profileRepository != null) {
        await _profileRepository!.upsertProfile(user.id, updates);
      } else {
        // Fallback if repository is not initialized
        await _client.from('profiles').upsert(updates);
      }

      // Mark profile as done in onboarding_progress
      await updateOnboardingProgress({'profile_done': true});

      AnalyticsService.instance.logAction(
        action: 'profile_updated',
        entityType: 'profile',
        entityId: user.id,
        details: {'fields': updates.keys.where((k) => k != 'id' && k != 'updated_at').toList()},
      );
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  Future<String> uploadAvatar(File imageFile) async {
    try {
      final user = currentUser;
      if (user == null) throw const AuthException('User not authenticated');

      // Validate file size (max 5MB)
      final fileSize = await imageFile.length();
      if (fileSize > 5 * 1024 * 1024) {
        throw Exception('Image too large. Maximum size is 5MB.');
      }

      final fileExt = imageFile.path.split('.').last;
      final fileName =
          '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await _client.storage
          .from('avatars')
          .upload(
            fileName,
            imageFile,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl = _client.storage.from('avatars').getPublicUrl(fileName);
      AnalyticsService.instance.logAction(
        action: 'avatar_uploaded',
        entityType: 'profile',
        entityId: user.id,
      );
      return publicUrl;
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // ONBOARDING PROGRESS
  // ---------------------------------------------------------------------------

  /// Upserts user onboarding progress. Valid keys: 
  /// profile_done, voice_enrolled, first_wingman, first_consultant
  /// These are remapped to schema columns: has_completed_welcome, has_set_voice,
  /// has_completed_tutorial, current_step
  Future<void> updateOnboardingProgress(Map<String, bool> updates) async {
    try {
      final user = currentUser;
      if (user == null) return;
      
      // Remap app-level keys to actual schema column names
      const keyMap = {
        'profile_done': 'has_completed_welcome',
        'voice_enrolled': 'has_set_voice',
        'first_wingman': 'has_completed_tutorial',
      };
      
      final row = <String, dynamic>{
        'user_id': user.id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      
      for (final entry in updates.entries) {
        final schemaKey = keyMap[entry.key];
        if (schemaKey != null) {
          row[schemaKey] = entry.value;
        } else if (entry.key == 'first_consultant') {
          // Store as current_step marker
          row['current_step'] = entry.value ? 'consultant_done' : null;
        }
      }
      
      await _client.from('onboarding_progress').upsert(row);
    } catch (e) {
      print('updateOnboardingProgress error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // ERROR HANDLING
  // ---------------------------------------------------------------------------

  Exception _handleAuthError(dynamic error) {
    if (error is AuthException) {
      return Exception(error.message);
    } else if (error is PostgrestException) {
      return Exception(error.message);
    } else if (error is StorageException) {
      return Exception(error.message);
    } else {
      return Exception('An unexpected error occurred: $error');
    }
  }
}
