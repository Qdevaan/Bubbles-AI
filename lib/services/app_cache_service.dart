import 'package:flutter/foundation.dart';
import '../cache/cache_entry.dart';

/// Shared in-memory cache replacing static fields on EntityScreen and
/// InsightsScreen. Registered at root so any screen can invalidate on
/// sign-out without needing a BuildContext.
class AppCacheService extends ChangeNotifier {
  // --- LEGACY FIELDS (To be deprecated) ---
  List<Map<String, dynamic>>? _entities;
  List<Map<String, dynamic>>? _events;
  List<Map<String, dynamic>>? _highlights;
  List<Map<String, dynamic>>? _notifications;
  String? _cacheUserId;

  // --- GENERIC CACHE ---
  final Map<String, CacheEntry> _cache = {};

  List<Map<String, dynamic>>? get entities => _entities;
  List<Map<String, dynamic>>? get events => _events;
  List<Map<String, dynamic>>? get highlights => _highlights;
  List<Map<String, dynamic>>? get notifications => _notifications;
  String? get cacheUserId => _cacheUserId;

  // --- GENERIC API ---

  /// Stores a value in memory with optional TTL.
  void setGeneric(CacheEntry entry) {
    _cache[entry.key] = entry;
    notifyListeners();
  }

  /// Retrieves a value from memory. Returns null if missing or expired.
  CacheEntry? getGeneric(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }
    return entry;
  }

  void deleteGeneric(String key) {
    if (_cache.containsKey(key)) {
      _cache.remove(key);
      notifyListeners();
    }
  }

  /// Removes all keys starting with [prefix].
  void purgeNamespace(String prefix) {
    _cache.removeWhere((key, _) => key.startsWith(prefix));
    notifyListeners();
  }

  /// Removes all keys scoped to [userId].
  void purgeUserScope(String userId) {
    purgeNamespace('user:$userId:');
    if (_cacheUserId == userId) {
      invalidateAll();
    }
  }

  // --- LEGACY SETTERS ---

  void setEntities(List<Map<String, dynamic>> data, String userId) {
    _entities = List.from(data);
    _cacheUserId = userId;
    notifyListeners();
  }

  void setInsights({
    required List<Map<String, dynamic>> events,
    required List<Map<String, dynamic>> highlights,
    required List<Map<String, dynamic>> notifications,
    required String userId,
  }) {
    _events = List.from(events);
    _highlights = List.from(highlights);
    _notifications = List.from(notifications);
    _cacheUserId = userId;
    notifyListeners();
  }

  void updateEvents(List<Map<String, dynamic>> data) {
    _events = List.from(data);
    notifyListeners();
  }

  void updateHighlights(List<Map<String, dynamic>> data) {
    _highlights = List.from(data);
    notifyListeners();
  }

  void updateNotifications(List<Map<String, dynamic>> data) {
    _notifications = List.from(data);
    notifyListeners();
  }

  void invalidateEntities() {
    _entities = null;
    notifyListeners();
  }

  void invalidateInsights() {
    _events = null;
    _highlights = null;
    _notifications = null;
    notifyListeners();
  }

  void invalidateAll() {
    _entities = null;
    _events = null;
    _highlights = null;
    _notifications = null;
    _cacheUserId = null;
    _cache.clear();
    notifyListeners();
  }
}
