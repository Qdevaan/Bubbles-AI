import '../cache/base_repository.dart';
import '../cache/cache_constants.dart';
import '../cache/cache_result.dart';
import '../cache/fetch_policy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EntityRepository extends BaseRepository {
  final SupabaseClient _client = Supabase.instance.client;

  EntityRepository({required super.l1, required super.l2});

  Future<CacheResult<List<Map<String, dynamic>>>> getEntities(String userId, {bool forceRefresh = false}) async {
    return fetch<List<Map<String, dynamic>>>(
      key: CacheKeys.entities(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.entities.inSeconds,
      schemaVersion: CacheSchemaVersion.entities,
      networkFetch: () async {
        final res = await _client
            .from('entities')
            .select('*, attributes:entity_attributes(*), relations:entity_relations!entity_relations_source_id_fkey(*)')
            .eq('user_id', userId)
            .order('display_name', ascending: true);
        return List<Map<String, dynamic>>.from(res);
      },
      fromJson: (json) => List<Map<String, dynamic>>.from(json),
      toJson: (data) => data,
    );
  }

  Future<void> deleteEntity(String entityId, String userId) async {
    await _client.from('entities').delete().eq('id', entityId);
    l1.deleteGeneric(CacheKeys.entities(userId));
    await l2.delete(CacheKeys.entities(userId));
  }
}
