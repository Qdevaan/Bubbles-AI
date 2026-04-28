import '../cache/base_repository.dart';
import '../cache/cache_constants.dart';
import '../cache/cache_result.dart';
import '../cache/fetch_policy.dart';
import '../services/api_service.dart';

class GraphRepository extends BaseRepository {
  final ApiService _api;

  GraphRepository({required ApiService api, required super.l1, required super.l2}) : _api = api;

  Future<CacheResult<Map<String, dynamic>>> getGraphExport(String userId, {bool forceRefresh = false}) async {
    return fetch<Map<String, dynamic>>(
      key: CacheKeys.graphExport(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.graphExport.inSeconds,
      schemaVersion: CacheSchemaVersion.graph,
      networkFetch: () async {
        final data = await _api.getGraphExport(userId);
        return data ?? {};
      },
      fromJson: (json) => Map<String, dynamic>.from(json),
      toJson: (data) => data,
    );
  }
}
