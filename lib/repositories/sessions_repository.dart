import '../cache/base_repository.dart';
import '../cache/cache_constants.dart';
import '../cache/cache_result.dart';
import '../cache/fetch_policy.dart';
import '../services/sessions_service.dart';
import '../services/api_service.dart';
import '../services/connection_service.dart';

class SessionsRepository extends BaseRepository {
  final SessionsService _service = SessionsService.instance;
  final ApiService _api;

  SessionsRepository({
    required super.l1,
    required super.l2,
    required ApiService api,
  }) : _api = api;

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

  Future<CacheResult<List<Map<String, dynamic>>>> getLiveSessions(String userId, {bool forceRefresh = false}) async {
    return fetch<List<Map<String, dynamic>>>(
      key: CacheKeys.liveSessions(userId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.sessions.inSeconds,
      schemaVersion: CacheSchemaVersion.sessions,
      networkFetch: () => _service.fetchLiveSessions(userId),
      fromJson: (json) => List<Map<String, dynamic>>.from(json),
      toJson: (data) => data,
    );
  }

  Future<CacheResult<Map<String, dynamic>?>> getSessionAnalytics(String sessionId, String userId, {bool forceRefresh = false}) async {
    return fetch<Map<String, dynamic>?>(
      key: CacheKeys.sessionAnalytics(sessionId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.sessionLogs.inSeconds,
      schemaVersion: CacheSchemaVersion.sessions,
      networkFetch: () => _api.getSessionAnalytics(sessionId),
      fromJson: (json) => json as Map<String, dynamic>?,
      toJson: (data) => data,
    );
  }

  Future<CacheResult<Map<String, dynamic>?>> getCoachingReport(String sessionId, String userId, {bool forceRefresh = false}) async {
    return fetch<Map<String, dynamic>?>(
      key: CacheKeys.coachingReport(sessionId),
      userId: userId,
      policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
      ttlSeconds: CacheTtl.sessionLogs.inSeconds,
      schemaVersion: CacheSchemaVersion.sessions,
      networkFetch: () => _api.getCoachingReport(sessionId),
      fromJson: (json) => json as Map<String, dynamic>?,
      toJson: (data) => data,
    );
  }

  Future<void> deleteSession(String sessionId, String userId) async {
    await _service.deleteSession(sessionId);
    // Invalidate caches
    l1.deleteGeneric(CacheKeys.consultantSessions(userId));
    l1.deleteGeneric(CacheKeys.liveSessions(userId));
    await l2.delete(CacheKeys.consultantSessions(userId));
    await l2.delete(CacheKeys.liveSessions(userId));
    
    l1.deleteGeneric(CacheKeys.sessionLogs(sessionId));
    l1.deleteGeneric(CacheKeys.sessionAnalytics(sessionId));
    l1.deleteGeneric(CacheKeys.coachingReport(sessionId));
    await l2.delete(CacheKeys.sessionLogs(sessionId));
    await l2.delete(CacheKeys.sessionAnalytics(sessionId));
    await l2.delete(CacheKeys.coachingReport(sessionId));
  }
}
