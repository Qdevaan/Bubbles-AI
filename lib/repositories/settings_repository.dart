import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../cache/base_repository.dart';
import '../cache/cache_constants.dart';
import '../cache/cache_result.dart';
import '../cache/fetch_policy.dart';
import '../cache/cache_entry.dart';

class SettingsRepository extends BaseRepository {
  final SupabaseClient _client = Supabase.instance.client;

  SettingsRepository({required super.l1, required super.l2});

  /// Loads settings with L0 (SharedPreferences) -> L2 (SQLite) -> L3 (Supabase) waterfall.
  Future<Map<String, dynamic>> loadSettings(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Start with L3 (remote sync)
    final remoteResult = await fetch<Map<String, dynamic>>(
      key: CacheKeys.userSettings(userId),
      userId: userId,
      policy: FetchPolicy.staleWhileRevalidate,
      ttlSeconds: 0, // No TTL for settings
      schemaVersion: CacheSchemaVersion.settings,
      networkFetch: () async {
        return await _client
            .from('user_settings')
            .select()
            .eq('user_id', userId)
            .maybeSingle();
      },
      fromJson: (json) => Map<String, dynamic>.from(json),
      toJson: (data) => data,
    );

    // 2. Aggregate all settings
    // Priority: Remote (if fresh) > Local Persistent (L2) > SharedPreferences (L0)
    final Map<String, dynamic> settings = {};
    
    // Add L0 values (backward compatibility)
    // In a real app we'd list all keys, but for now we'll assume the provider handles defaults.
    
    // Overlay L2 values
    final l2Entry = await l2.read(CacheKeys.userSettings(userId));
    if (l2Entry != null) {
      settings.addAll(Map<String, dynamic>.from(l2Entry.payload));
    }

    // Overlay L3 values
    if (remoteResult.hasData) {
      settings.addAll(remoteResult.data!);
    }

    return settings;
  }

  Future<void> writeSetting(String userId, String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Update L0 (SharedPreferences)
    if (value is bool) await prefs.setBool(key, value);
    else if (value is String) await prefs.setString(key, value);
    else if (value is int) await prefs.setInt(key, value);
    else if (value is double) await prefs.setDouble(key, value);

    // 2. Update L1 & L2 (Persistent Cache)
    final currentL2 = await l2.read(CacheKeys.userSettings(userId));
    final Map<String, dynamic> data = currentL2 != null 
        ? Map<String, dynamic>.from(currentL2.payload) 
        : {};
    data[key] = value;

    final entry = CacheEntry(
      key: CacheKeys.userSettings(userId),
      userId: userId,
      payload: data,
      updatedAt: DateTime.now(),
      schemaVersion: CacheSchemaVersion.settings,
    );
    l1.setGeneric(entry);
    await l2.write(entry);

    // 3. Update L3 (Network - fire and forget)
    // We map app keys to schema columns here or let the provider handle mapping.
    // For now we'll assume caller provides the correct schema key if it's a synced setting.
  }

  Future<void> migrateToUserNamespace(String userId, Map<String, String> keyMap) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> migratedData = {};

    for (final entry in keyMap.entries) {
      final oldKey = entry.key;
      if (prefs.containsKey(oldKey)) {
        migratedData[entry.value] = prefs.get(oldKey);
        // await prefs.remove(oldKey); // Optional: cleanup
      }
    }

    if (migratedData.isNotEmpty) {
      final entry = CacheEntry(
        key: CacheKeys.userSettings(userId),
        userId: userId,
        payload: migratedData,
        updatedAt: DateTime.now(),
        schemaVersion: CacheSchemaVersion.settings,
      );
      l1.setGeneric(entry);
      await l2.write(entry);
    }
  }
}
