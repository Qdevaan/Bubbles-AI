import '../cache/base_repository.dart';
import '../cache/cache_constants.dart';
import '../cache/cache_result.dart';
import '../cache/fetch_policy.dart';
import '../services/api_service.dart';

class GamificationRepository extends BaseRepository {
  final ApiService _api;

  GamificationRepository({required ApiService api, required super.l1, required super.l2}) : _api = api;

  Future<CacheResult<Map<String, dynamic>>> getGamification(String userId, {bool forceRefresh = false}) async {
    return fetch<Map<String, dynamic>>(
      key: CacheKeys.gamification(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.gamification.inSeconds,
      schemaVersion: CacheSchemaVersion.gamification,
      networkFetch: () async {
        final data = await _api.getGamification(userId);
        return data ?? {};
      },
      fromJson: (json) => Map<String, dynamic>.from(json),
      toJson: (data) => data,
    );
  }

  Future<CacheResult<Map<String, dynamic>>> getQuests(String userId, {bool forceRefresh = false}) async {
    return fetch<Map<String, dynamic>>(
      key: CacheKeys.quests(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.quests.inSeconds,
      schemaVersion: CacheSchemaVersion.gamification,
      networkFetch: () async {
        final data = await _api.getQuests(userId);
        return data ?? {};
      },
      fromJson: (json) => Map<String, dynamic>.from(json),
      toJson: (data) => data,
    );
  }

  Future<CacheResult<Map<String, dynamic>>> getPerformanceSummary(String userId, {bool forceRefresh = false}) async {
    return fetch<Map<String, dynamic>>(
      key: CacheKeys.performance(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.performance.inSeconds,
      schemaVersion: CacheSchemaVersion.gamification,
      networkFetch: () async {
        final data = await _api.getPerformanceSummary(userId);
        return data ?? {};
      },
      fromJson: (json) => Map<String, dynamic>.from(json),
      toJson: (data) => data,
    );
  }
}
