// Purpose: Repository for suggested scenarios — caches the server response to avoid redundant fetches on tab switches.
import '../cache/base_repository.dart';
import '../cache/cache_constants.dart';
import '../cache/cache_result.dart';
import '../cache/fetch_policy.dart';
import '../services/api_service.dart';

/// SWR cache wrapper around the suggested-scenarios feed.
///
/// Generation/start mutations are not cached — they go straight through the
/// API. Only the read-side feed benefits from caching.
class ScenariosRepository extends BaseRepository {
  final ApiService _api;

  ScenariosRepository({
    required super.l1,
    required super.l2,
    required ApiService api,
  }) : _api = api;

  Future<CacheResult<List<Map<String, dynamic>>>> getSuggested({
    required String userId,
    int limit = 30,
    bool forceRefresh = false,
  }) async {
    return fetch<List<Map<String, dynamic>>>(
      key: CacheKeys.scenariosSuggested(userId),
      userId: userId,
      policy: forceRefresh
          ? FetchPolicy.networkFirst
          : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.scenarios.inSeconds,
      schemaVersion: CacheSchemaVersion.scenarios,
      networkFetch: () =>
          _api.getScenarios(status: 'suggested', limit: limit, offset: 0),
      fromJson: (json) => List<Map<String, dynamic>>.from(json),
      toJson: (data) => data,
    );
  }

  Future<void> invalidateSuggested(String userId) async {
    final key = CacheKeys.scenariosSuggested(userId);
    l1.deleteGeneric(key);
    await l2.delete(key);
  }
}
