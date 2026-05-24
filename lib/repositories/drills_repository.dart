import '../cache/base_repository.dart';
import '../cache/cache_constants.dart';
import '../cache/cache_result.dart';
import '../cache/fetch_policy.dart';
import '../services/api_service.dart';

/// SWR cache wrapper around the drills queue endpoint.
///
/// The screen consumes this through [DrillsProvider]. A short TTL keeps the
/// reviewable card list fresh while still avoiding a network round-trip on
/// every navigation back into the drills screen.
class DrillsRepository extends BaseRepository {
  final ApiService _api;

  DrillsRepository({
    required super.l1,
    required super.l2,
    required ApiService api,
  }) : _api = api;

  Future<CacheResult<Map<String, dynamic>>> getQueue({
    required String userId,
    int limit = 50,
    bool includeUpcoming = false,
    bool forceRefresh = false,
  }) async {
    return fetch<Map<String, dynamic>>(
      key: includeUpcoming
          ? '${CacheKeys.drillsQueue(userId)}:upcoming'
          : CacheKeys.drillsQueue(userId),
      userId: userId,
      policy: forceRefresh
          ? FetchPolicy.networkFirst
          : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.drillsQueue.inSeconds,
      schemaVersion: CacheSchemaVersion.drills,
      networkFetch: () async => await _api.getDrillsQueue(
        limit: limit,
        includeUpcoming: includeUpcoming,
      ),
      fromJson: (json) => Map<String, dynamic>.from(json),
      toJson: (data) => data,
    );
  }

  /// Drops cached queues for [userId] — call after a successful review/retire
  /// so the next screen open does not show a stale card list.
  Future<void> invalidateQueue(String userId) async {
    final dueKey = CacheKeys.drillsQueue(userId);
    final upcomingKey = '$dueKey:upcoming';
    l1.deleteGeneric(dueKey);
    l1.deleteGeneric(upcomingKey);
    await l2.delete(dueKey);
    await l2.delete(upcomingKey);
  }
}
