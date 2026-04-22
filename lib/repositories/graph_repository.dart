import '../cache/base_repository.dart';
import '../cache/cache_constants.dart';
import '../cache/cache_result.dart';
import '../cache/fetch_policy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GraphRepository extends BaseRepository {
  final SupabaseClient _client = Supabase.instance.client;

  GraphRepository({required super.l1, required super.l2});

  Future<CacheResult<Map<String, dynamic>>> getGraphExport(String userId, {bool forceRefresh = false}) async {
    return fetch<Map<String, dynamic>>(
      key: CacheKeys.graphExport(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.graphExport.inSeconds,
      schemaVersion: CacheSchemaVersion.graph,
      networkFetch: () async {
        return await _client.rpc('export_knowledge_graph_json', params: {'p_user_id': userId});
      },
      fromJson: (json) => Map<String, dynamic>.from(json),
      toJson: (data) => data,
    );
  }
}
