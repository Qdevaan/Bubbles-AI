// Purpose: State manager for user-defined tags — loads, creates, and deletes tags, and links them to sessions and entities.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

class TagsProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _tags = [];
  List<Map<String, dynamic>> get tags => List.unmodifiable(_tags);

  bool _loaded = false;
  bool get loaded => _loaded;

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
