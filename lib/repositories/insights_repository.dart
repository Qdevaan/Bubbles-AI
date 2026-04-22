import '../cache/base_repository.dart';
import '../cache/cache_constants.dart';
import '../cache/cache_result.dart';
import '../cache/fetch_policy.dart';
import '../services/insights_service.dart';

class InsightsRepository extends BaseRepository {
  final InsightsService _service = InsightsService.instance;

  InsightsRepository({required super.l1, required super.l2});

  Future<CacheResult<List<Map<String, dynamic>>>> getEvents(String userId, {bool forceRefresh = false}) async {
    return fetch<List<Map<String, dynamic>>>(
      key: CacheKeys.insightsEvents(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.insights.inSeconds,
      schemaVersion: CacheSchemaVersion.insights,
      networkFetch: () => _service.fetchEvents(userId),
      fromJson: (json) => List<Map<String, dynamic>>.from(json),
      toJson: (data) => data,
    );
  }

  Future<CacheResult<List<Map<String, dynamic>>>> getHighlights(String userId, {bool forceRefresh = false}) async {
    return fetch<List<Map<String, dynamic>>>(
      key: CacheKeys.insightsHighlights(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.insights.inSeconds,
      schemaVersion: CacheSchemaVersion.insights,
      networkFetch: () => _service.fetchHighlights(userId),
      fromJson: (json) => List<Map<String, dynamic>>.from(json),
      toJson: (data) => data,
    );
  }

  Future<CacheResult<List<Map<String, dynamic>>>> getNotifications(String userId, {bool forceRefresh = false}) async {
    return fetch<List<Map<String, dynamic>>>(
      key: CacheKeys.insightsNotifications(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.insights.inSeconds,
      schemaVersion: CacheSchemaVersion.insights,
      networkFetch: () => _service.fetchNotifications(userId),
      fromJson: (json) => List<Map<String, dynamic>>.from(json),
      toJson: (data) => data,
    );
  }

  Future<void> deleteItem(String table, String id, String userId) async {
    await _service.deleteItem(table, id);
    // Invalidate caches
    if (table == 'events') l1.deleteGeneric(CacheKeys.insightsEvents(userId));
    else if (table == 'highlights') l1.deleteGeneric(CacheKeys.insightsHighlights(userId));
    else if (table == 'notifications') l1.deleteGeneric(CacheKeys.insightsNotifications(userId));
    
    // We could also delete from L2 here, but L1 delete will force re-read from L2 which might be stale,
    // so we should delete from both.
    if (table == 'events') await l2.delete(CacheKeys.insightsEvents(userId));
    else if (table == 'highlights') await l2.delete(CacheKeys.insightsHighlights(userId));
    else if (table == 'notifications') await l2.delete(CacheKeys.insightsNotifications(userId));
  }
}
