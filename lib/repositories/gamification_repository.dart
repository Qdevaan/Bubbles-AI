import '../cache/base_repository.dart';
import '../cache/cache_constants.dart';
import '../cache/cache_result.dart';
import '../cache/fetch_policy.dart';
import '../services/api_service.dart';

/// Today's ISO date string (YYYY-MM-DD) used to build a date-scoped cache key
/// so quests from yesterday are never served from cache.
String _todayIso() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

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
        return data ?? _defaultGamificationProfile();
      },
      fromJson: (json) => Map<String, dynamic>.from(json),
      toJson: (data) => data,
    );
  }

  Map<String, dynamic> _defaultGamificationProfile() => {
    'xp': 0,
    'level': 1,
    'xp_current_level': 0,
    'xp_next_level': 100,
    'xp_to_next_level': 100,
    'xp_progress_pct': 0.0,
    'current_streak': 0,
    'longest_streak': 0,
    'streak_freezes': 1,
    'last_active_date': null,
    'xp_spent': 0,
    'xp_balance': 0,
    'badges': <Map<String, dynamic>>[],
    'recent_xp': <Map<String, dynamic>>[],
    'stats': <String, dynamic>{'total_sessions': 0, 'total_questions': 0},
  };

  Future<CacheResult<Map<String, dynamic>>> getQuests(String userId, {bool forceRefresh = false}) async {
    // Include today's date in the cache key — yesterday's quests are automatically stale.
    final dateKey = '${CacheKeys.quests(userId)}:${_todayIso()}';
    return fetch<Map<String, dynamic>>(
      key: dateKey,
      userId: userId,
      // Always networkFirst: the backend is idempotent (creates quests if not yet assigned)
      // and quests must always be date-fresh on first access per day.
      policy: FetchPolicy.networkFirst,
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
