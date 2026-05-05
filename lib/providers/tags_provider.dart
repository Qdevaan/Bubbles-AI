import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

/// Manages user-defined tags and session-tag associations (schema_v2 I1-I3).
class TagsProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _tags = [];
  List<Map<String, dynamic>> get tags => List.unmodifiable(_tags);

  bool _loaded = false;
  bool get loaded => _loaded;

  // ── Load all tags for the current user ────────────────────────────────────
  Future<void> loadTags() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    try {
      final res = await _supabase
          .from('tags')
          .select('id, name, color, created_at')
          .eq('user_id', user.id)
          .order('created_at', ascending: true);
      _tags = List<Map<String, dynamic>>.from(res);
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('TagsProvider.loadTags: $e');
    }
  }

  // ── Create a new tag ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> createTag(String name, String color) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return null;
    try {
      final res = await _supabase.from('tags').insert({
        'user_id': user.id,
        'name': name.trim(),
        'color': color,
      }).select().single();
      _tags.add(res);
      notifyListeners();
      return res;
    } catch (e) {
      debugPrint('TagsProvider.createTag: $e');
      return null;
    }
  }

  // ── Delete a tag (cascades via DB to session_tags / entity_tags) ──────────
  Future<bool> deleteTag(String tagId) async {
    try {
      await _supabase.from('tags').delete().eq('id', tagId);
      _tags.removeWhere((t) => t['id'] == tagId);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('TagsProvider.deleteTag: $e');
      return false;
    }
  }

  // ── Tag a session ─────────────────────────────────────────────────────────
  Future<bool> tagSession(String sessionId, String tagId) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return false;
    try {
      await _supabase.from('session_tags').upsert({
        'session_id': sessionId,
        'tag_id': tagId,
        'user_id': user.id,
      });
      return true;
    } catch (e) {
      debugPrint('TagsProvider.tagSession: $e');
      return false;
    }
  }

  // ── Untag a session ───────────────────────────────────────────────────────
  Future<bool> untagSession(String sessionId, String tagId) async {
    try {
      await _supabase
          .from('session_tags')
          .delete()
          .eq('session_id', sessionId)
          .eq('tag_id', tagId);
      return true;
    } catch (e) {
      debugPrint('TagsProvider.untagSession: $e');
      return false;
    }
  }

  // ── Get tags for a specific session ──────────────────────────────────────
  Future<List<Map<String, dynamic>>> getTagsForSession(String sessionId) async {
    try {
      final res = await _supabase
          .from('session_tags')
          .select('tag_id, tags(id, name, color)')
          .eq('session_id', sessionId);
      return List<Map<String, dynamic>>.from(
        (res as List).map((r) => r['tags'] as Map<String, dynamic>),
      );
    } catch (e) {
      debugPrint('TagsProvider.getTagsForSession: $e');
      return [];
    }
  }

  // ── Tag an entity ─────────────────────────────────────────────────────────
  Future<bool> tagEntity(String entityId, String tagId) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return false;
    try {
      await _supabase.from('entity_tags').upsert({
        'entity_id': entityId,
        'tag_id': tagId,
        'user_id': user.id,
      });
      return true;
    } catch (e) {
      debugPrint('TagsProvider.tagEntity: $e');
      return false;
    }
  }

  // ── Untag an entity ───────────────────────────────────────────────────────
  Future<bool> untagEntity(String entityId, String tagId) async {
    try {
      await _supabase
          .from('entity_tags')
          .delete()
          .eq('entity_id', entityId)
          .eq('tag_id', tagId);
      return true;
    } catch (e) {
      debugPrint('TagsProvider.untagEntity: $e');
      return false;
    }
  }

  // ── Get tags for a specific entity ──────────────────────────────────────
  Future<List<Map<String, dynamic>>> getTagsForEntity(String entityId) async {
    try {
      final res = await _supabase
          .from('entity_tags')
          .select('tag_id, tags(id, name, color)')
          .eq('entity_id', entityId);
      return List<Map<String, dynamic>>.from(
        (res as List).map((r) => r['tags'] as Map<String, dynamic>),
      );
    } catch (e) {
      debugPrint('TagsProvider.getTagsForEntity: $e');
      return [];
    }
  }
}
