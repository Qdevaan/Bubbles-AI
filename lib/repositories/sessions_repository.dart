import '../cache/base_repository.dart';
import '../cache/cache_constants.dart';
import '../cache/cache_result.dart';
import '../cache/fetch_policy.dart';
import '../services/sessions_service.dart';

class SessionsRepository extends BaseRepository {
  final SessionsService _service = SessionsService.instance;

  SessionsRepository({required super.l1, required super.l2});

  Future<CacheResult<List<Map<String, dynamic>>>> getConsultantSessions(String userId, {bool forceRefresh = false}) async {
    return fetch<List<Map<String, dynamic>>>(
      key: CacheKeys.consultantSessions(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.sessions.inSeconds,
      schemaVersion: CacheSchemaVersion.sessions,
      networkFetch: () => _service.fetchConsultantSessions(userId),
      fromJson: (json) => List<Map<String, dynamic>>.from(json),
      toJson: (data) => data,
    );
  }

  Future<CacheResult<List<Map<String, dynamic>>>> getSessionLogs(String sessionId, bool isConsultant, String userId, {bool forceRefresh = false}) async {
    return fetch<List<Map<String, dynamic>>>(
      key: CacheKeys.sessionLogs(sessionId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.sessionLogs.inSeconds,
      schemaVersion: CacheSchemaVersion.sessions,
      networkFetch: () => _service.fetchSessionLogs(sessionId: sessionId, isConsultant: isConsultant),
      fromJson: (json) => List<Map<String, dynamic>>.from(json),
      toJson: (data) => data,
    );
  }

  Future<void> deleteSession(String sessionId, String userId) async {
    await _service.deleteSession(sessionId);
    // Invalidate consultant sessions list
    l1.deleteGeneric(CacheKeys.consultantSessions(userId));
    await l2.delete(CacheKeys.consultantSessions(userId));
    // Also delete the specific log cache for this session
    l1.deleteGeneric(CacheKeys.sessionLogs(sessionId));
    await l2.delete(CacheKeys.sessionLogs(sessionId));
  }
}
