import 'package:supabase_flutter/supabase_flutter.dart';
import '../cache/base_repository.dart';
import '../cache/cache_constants.dart';
import '../cache/cache_result.dart';
import '../cache/fetch_policy.dart';
import '../services/api_service.dart';
import '../utils/xp_math.dart';

class GamificationRepository extends BaseRepository {
  final ApiService _api;
  final SupabaseClient _client = Supabase.instance.client;

  GamificationRepository({required ApiService api, required super.l1, required super.l2}) : _api = api;

  Future<CacheResult<Map<String, dynamic>>> getGamification(String userId, {bool forceRefresh = false}) async {
    return fetch<Map<String, dynamic>>(
      key: CacheKeys.gamification(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.gamification.inSeconds,
      schemaVersion: CacheSchemaVersion.gamification,
      networkFetch: () async {
        final results = await Future.wait<dynamic>([
          _client.from('user_gamification').select('*').eq('user_id', userId).maybeSingle(),
          _client.from('user_achievements').select('achievement_id, awarded_at, achievements(id, title, description, icon, category, tier, code)').eq('user_id', userId),
          _client.from('xp_transactions').select('amount, reason, created_at').eq('user_id', userId).order('created_at', ascending: false).limit(10),
        ]);

        final profileRes = results[0];
        if (profileRes == null) return _defaultGamificationProfile();

        final profile = Map<String, dynamic>.from(profileRes as Map);
        final totalXp = (profile['total_xp'] as num? ?? 0).toInt();
        final xpSpent = (profile['xp_spent'] as num? ?? 0).toInt();
        final level = levelForXp(totalXp);
        final xpCurrentLevel = xpForLevel(level);
        final xpNextLevel = xpForLevel(level + 1);
        final range = xpNextLevel - xpCurrentLevel;

        final badgesRes = results[1] as List;
        final badges = badgesRes.map((row) {
          final rawAchiev = row['achievements'];
          final a = rawAchiev != null ? Map<String, dynamic>.from(rawAchiev as Map) : <String, dynamic>{};
          return <String, dynamic>{
            'id': a['id'] ?? row['achievement_id'],
            'title': a['title'] ?? '',
            'description': a['description'] ?? '',
            'icon': a['icon'] ?? '🏆',
            'category': a['category'] ?? 'general',
            'tier': a['tier'] ?? 'bronze',
            'code': a['code'] ?? '',
            'awarded_at': row['awarded_at'],
          };
        }).toList();

        final xpRes = results[2] as List;

        return <String, dynamic>{
          'xp': totalXp,
          'level': level,
          'xp_current_level': xpCurrentLevel,
          'xp_next_level': xpNextLevel,
          'xp_to_next_level': xpNextLevel - totalXp,
          'xp_progress_pct': range <= 0 ? 1.0 : ((totalXp - xpCurrentLevel) / range).clamp(0.0, 1.0),
          'current_streak': profile['current_streak'] ?? 0,
          'longest_streak': profile['longest_streak'] ?? 0,
          'streak_freezes': profile['streak_freezes'] ?? 0,
          'last_active_date': profile['last_active_date'],
          'xp_spent': xpSpent,
          'xp_balance': totalXp - xpSpent,
          'badges': badges,
          'recent_xp': List<Map<String, dynamic>>.from(xpRes),
          'stats': {
            'total_sessions': profile['total_sessions'] ?? 0,
            'total_questions': profile['total_questions'] ?? 0,
          },
        };
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
