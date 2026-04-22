import '../cache/base_repository.dart';
import '../cache/cache_constants.dart';
import '../cache/cache_entry.dart';
import '../cache/cache_result.dart';
import '../cache/fetch_policy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeRepository extends BaseRepository {
  final SupabaseClient _client = Supabase.instance.client;

  HomeRepository({required super.l1, required super.l2});

  Future<CacheResult<List<Map<String, dynamic>>>> getEvents(String userId, {bool forceRefresh = false}) async {
    return fetch<List<Map<String, dynamic>>>(
      key: CacheKeys.homeEvents(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.homeEvents.inSeconds,
      schemaVersion: CacheSchemaVersion.home,
      networkFetch: () async {
        final res = await _client
            .from('events')
            .select()
            .eq('user_id', userId)
            .order('start_time', ascending: true);
        return List<Map<String, dynamic>>.from(res);
      },
      fromJson: (json) => List<Map<String, dynamic>>.from(json),
      toJson: (data) => data,
    );
  }

  Future<CacheResult<List<Map<String, dynamic>>>> getHighlights(String userId, {bool forceRefresh = false}) async {
    return fetch<List<Map<String, dynamic>>>(
      key: CacheKeys.homeHighlights(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.homeHighlights.inSeconds,
      schemaVersion: CacheSchemaVersion.home,
      networkFetch: () async {
        final res = await _client
            .from('highlights')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(res);
      },
      fromJson: (json) => List<Map<String, dynamic>>.from(json),
      toJson: (data) => data,
    );
  }

  Future<CacheResult<List<Map<String, dynamic>>>> getNotifications(String userId, {bool forceRefresh = false}) async {
    return fetch<List<Map<String, dynamic>>>(
      key: CacheKeys.homeNotifications(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.homeNotifications.inSeconds,
      schemaVersion: CacheSchemaVersion.home,
      networkFetch: () async {
        final res = await _client
            .from('notifications')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(res);
      },
      fromJson: (json) => List<Map<String, dynamic>>.from(json),
      toJson: (data) => data,
    );
  }

  /// Manually update highlights cache (for realtime synchronization)
  Future<void> updateHighlightsCache(String userId, Map<String, dynamic> newRecord) async {
    final key = CacheKeys.homeHighlights(userId);
    final entry = l1.getGeneric(key);
    final current = entry != null ? List<Map<String, dynamic>>.from(entry.payload) : <Map<String, dynamic>>[];
    final updated = [newRecord, ...current].take(20).toList(); 
    
    final newEntry = CacheEntry(
      key: key,
      userId: userId,
      payload: updated,
      updatedAt: DateTime.now(),
      ttlSeconds: CacheTtl.homeHighlights.inSeconds,
      schemaVersion: CacheSchemaVersion.home,
    );
    
    l1.setGeneric(newEntry);
    await l2.write(newEntry);
  }

  /// Manually update notifications cache (for realtime synchronization)
  Future<void> updateNotificationsCache(String userId, Map<String, dynamic> newRecord) async {
    final key = CacheKeys.homeNotifications(userId);
    final entry = l1.getGeneric(key);
    final current = entry != null ? List<Map<String, dynamic>>.from(entry.payload) : <Map<String, dynamic>>[];
    final updated = [newRecord, ...current].take(20).toList();

    final newEntry = CacheEntry(
      key: key,
      userId: userId,
      payload: updated,
      updatedAt: DateTime.now(),
      ttlSeconds: CacheTtl.homeNotifications.inSeconds,
      schemaVersion: CacheSchemaVersion.home,
    );

    l1.setGeneric(newEntry);
    await l2.write(newEntry);
  }
}
