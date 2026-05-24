import '../cache/base_repository.dart';
import '../cache/cache_constants.dart';
import '../cache/cache_result.dart';
import '../cache/fetch_policy.dart';
import '../services/api_service.dart';

/// SWR cache wrapper around the longitudinal progress dashboard endpoint.
///
/// Cache keys are scoped per `range` (`30d` / `90d` / `365d`) so toggling a
/// range never overwrites the data for the other ranges.
class DashboardRepository extends BaseRepository {
  final ApiService _api;

  DashboardRepository({
    required super.l1,
    required super.l2,
    required ApiService api,
  }) : _api = api;

  /// Returns the dashboard payload alongside the upstream HTTP status code
  /// so the provider can surface the same error toasts as before. Cache is
  /// populated only on 200.
  Future<({CacheResult<Map<String, dynamic>> result, int statusCode})> getDashboard({
    required String userId,
    required String range,
    bool forceRefresh = false,
  }) async {
    int statusCode = 200;
    final result = await fetch<Map<String, dynamic>>(
      key: CacheKeys.dashboard(userId, range),
      userId: userId,
      policy: forceRefresh
          ? FetchPolicy.networkFirst
          : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.dashboard.inSeconds,
      schemaVersion: CacheSchemaVersion.dashboard,
      networkFetch: () async {
        final res = await _api.getDashboard(range: range);
        statusCode = res.statusCode;
        if (res.statusCode == 200 && res.data != null) {
          return res.data;
        }
        return null;
      },
      fromJson: (json) => Map<String, dynamic>.from(json),
      toJson: (data) => data,
    );
    return (result: result, statusCode: statusCode);
  }
}
