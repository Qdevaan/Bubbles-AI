import '../cache/base_repository.dart';
import '../cache/cache_constants.dart';
import '../cache/cache_result.dart';
import '../cache/fetch_policy.dart';
import '../cache/cache_entry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileRepository extends BaseRepository {
  final SupabaseClient _client = Supabase.instance.client;

  ProfileRepository({required super.l1, required super.l2});

  Future<CacheResult<Map<String, dynamic>>> getProfile(String userId, {bool forceRefresh = false}) async {
    return fetch<Map<String, dynamic>>(
      key: CacheKeys.userProfile(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.cacheFirst,
      ttlSeconds: CacheTtl.profile.inSeconds,
      schemaVersion: CacheSchemaVersion.profile,
      networkFetch: () async {
        return await _client
            .from('profiles')
            .select()
            .eq('id', userId)
            .maybeSingle();
      },
      fromJson: (json) => Map<String, dynamic>.from(json),
      toJson: (data) => data,
    );
  }

  Future<void> upsertProfile(String userId, Map<String, dynamic> updates) async {
    // 1. Update Network
    await _client.from('profiles').upsert(updates);

    // 2. Update Cache (Write-through)
    final existing = await getProfile(userId);
    final currentData = existing.data ?? {};
    final newData = {...currentData, ...updates};

    final entry = CacheEntry(
      key: CacheKeys.userProfile(userId),
      userId: userId,
      payload: newData,
      updatedAt: DateTime.now(),
      ttlSeconds: CacheTtl.profile.inSeconds,
      schemaVersion: CacheSchemaVersion.profile,
    );

    l1.setGeneric(entry);
    await l2.write(entry);
  }

  Future<void> clearUserCache(String userId) async {
    l1.purgeUserScope(userId);
    await l2.purgeUserScope(userId);
  }
}
