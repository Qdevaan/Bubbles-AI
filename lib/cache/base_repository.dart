import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/app_cache_service.dart';
import 'persistent_cache_service.dart';
import 'cache_entry.dart';
import 'cache_result.dart';
import 'fetch_policy.dart';
import 'payload_codec.dart';

abstract class BaseRepository {
  final AppCacheService l1;
  final PersistentCacheService l2;

  BaseRepository({required this.l1, required this.l2});

  void _log(String message) {
    debugPrint('[BaseRepository] $message');
  }

  /// The main entry point for fetching data with cache orchestration.
  Future<CacheResult<T>> fetch<T>({
    required String key,
    required String? userId,
    required FetchPolicy policy,
    required int ttlSeconds,
    required int schemaVersion,
    required Future<T?> Function() networkFetch,
    required T Function(dynamic json) fromJson,
    required dynamic Function(T value) toJson,
    void Function(T fresh)? onRefreshed,
  }) async {
    switch (policy) {
      case FetchPolicy.cacheFirst:
        return _fetchCacheFirst(
          key: key,
          userId: userId,
          ttlSeconds: ttlSeconds,
          schemaVersion: schemaVersion,
          networkFetch: networkFetch,
          fromJson: fromJson,
          toJson: toJson,
          onRefreshed: onRefreshed,
        );
      case FetchPolicy.staleWhileRevalidate:
        return _fetchStaleWhileRevalidate(
          key: key,
          userId: userId,
          ttlSeconds: ttlSeconds,
          schemaVersion: schemaVersion,
          networkFetch: networkFetch,
          fromJson: fromJson,
          toJson: toJson,
          onRefreshed: onRefreshed,
        );
      case FetchPolicy.networkFirst:
        return _fetchNetworkFirst(
          key: key,
          userId: userId,
          ttlSeconds: ttlSeconds,
          schemaVersion: schemaVersion,
          networkFetch: networkFetch,
          fromJson: fromJson,
          toJson: toJson,
          onRefreshed: onRefreshed,
        );
      case FetchPolicy.cacheOnly:
        return _fetchCacheOnly(
          key: key,
          fromJson: fromJson,
        );
    }
  }

  Future<CacheResult<T>> _fetchCacheFirst<T>({
    required String key,
    required String? userId,
    required int ttlSeconds,
    required int schemaVersion,
    required Future<T?> Function() networkFetch,
    required T Function(dynamic json) fromJson,
    required dynamic Function(T value) toJson,
    void Function(T fresh)? onRefreshed,
  }) async {
    // 1. Try L1
    final l1Entry = l1.getGeneric(key);
    if (l1Entry != null && !l1Entry.isExpired) {
      _log('HIT (Memory): $key');
      return CacheResult(
        data: fromJson(l1Entry.payload),
        source: CacheSource.memory,
        ageMs: l1Entry.ageMs,
      );
    }

    // 2. Try L2
    final l2Entry = await l2.read(key);
    if (l2Entry != null && !l2Entry.isExpired) {
      _log('HIT (Disk): $key');
      l1.setGeneric(l2Entry); // Populate L1
      return CacheResult(
        data: fromJson(l2Entry.payload),
        source: CacheSource.disk,
        ageMs: l2Entry.ageMs,
      );
    }

    _log('MISS (Network): $key');
    // 3. Try L3
    try {
      final networkData = await networkFetch();
      if (networkData != null) {
        final entry = CacheEntry(
          key: key,
          userId: userId,
          payload: toJson(networkData),
          updatedAt: DateTime.now(),
          ttlSeconds: ttlSeconds,
          schemaVersion: schemaVersion,
          payloadHash: PayloadCodec.computeHash(toJson(networkData)),
        );
        l1.setGeneric(entry);
        await l2.write(entry);
        return CacheResult(
          data: networkData,
          source: CacheSource.network,
        );
      }
    } catch (e) {
      // Return stale if network fails
      if (l1Entry != null) return CacheResult(data: fromJson(l1Entry.payload), source: CacheSource.memory, isStale: true, ageMs: l1Entry.ageMs);
      if (l2Entry != null) return CacheResult(data: fromJson(l2Entry.payload), source: CacheSource.disk, isStale: true, ageMs: l2Entry.ageMs);
    }

    return CacheResult(source: CacheSource.none);
  }

  Future<CacheResult<T>> _fetchStaleWhileRevalidate<T>({
    required String key,
    required String? userId,
    required int ttlSeconds,
    required int schemaVersion,
    required Future<T?> Function() networkFetch,
    required T Function(dynamic json) fromJson,
    required dynamic Function(T value) toJson,
    void Function(T fresh)? onRefreshed,
  }) async {
    // 1. Check Cache (L1 or L2)
    final l1Entry = l1.getGeneric(key);
    CacheEntry? cachedEntry = l1Entry;
    CacheSource source = CacheSource.memory;

    if (cachedEntry == null) {
      cachedEntry = await l2.read(key);
      source = CacheSource.disk;
      if (cachedEntry != null) {
        _log('HIT (Disk/SWR): $key');
        l1.setGeneric(cachedEntry);
      } else {
        _log('MISS (Network/SWR-Initial): $key');
      }
    } else {
      _log('HIT (Memory/SWR): $key');
    }

    // 2. If we have cached data, return it immediately as stale (if expired) or fresh
    final bool hasCachedData = cachedEntry != null;
    final T? cachedData = hasCachedData ? fromJson(cachedEntry!.payload) : null;

    // Trigger background refresh
    unawaited(_refreshNetwork(
      key: key,
      userId: userId,
      ttlSeconds: ttlSeconds,
      schemaVersion: schemaVersion,
      networkFetch: networkFetch,
      toJson: toJson,
      oldHash: cachedEntry?.payloadHash,
      onRefreshed: (fresh) {
        if (onRefreshed != null) onRefreshed(fresh);
      },
    ));

    if (hasCachedData) {
      return CacheResult(
        data: cachedData,
        source: source,
        isStale: cachedEntry!.isExpired,
        ageMs: cachedEntry.ageMs,
      );
    }

    // 3. If no cache, we wait for network (first time)
    try {
      final networkData = await networkFetch();
      if (networkData != null) {
        final entry = CacheEntry(
          key: key,
          userId: userId,
          payload: toJson(networkData),
          updatedAt: DateTime.now(),
          ttlSeconds: ttlSeconds,
          schemaVersion: schemaVersion,
          payloadHash: PayloadCodec.computeHash(toJson(networkData)),
        );
        l1.setGeneric(entry);
        await l2.write(entry);
        return CacheResult(
          data: networkData,
          source: CacheSource.network,
        );
      }
    } catch (e) {
      // Error
    }

    return CacheResult(source: CacheSource.none);
  }

  Future<CacheResult<T>> _fetchNetworkFirst<T>({
    required String key,
    required String? userId,
    required int ttlSeconds,
    required int schemaVersion,
    required Future<T?> Function() networkFetch,
    required T Function(dynamic json) fromJson,
    required dynamic Function(T value) toJson,
    void Function(T fresh)? onRefreshed,
  }) async {
    try {
      final networkData = await networkFetch();
      if (networkData != null) {
        final entry = CacheEntry(
          key: key,
          userId: userId,
          payload: toJson(networkData),
          updatedAt: DateTime.now(),
          ttlSeconds: ttlSeconds,
          schemaVersion: schemaVersion,
          payloadHash: PayloadCodec.computeHash(toJson(networkData)),
        );
        l1.setGeneric(entry);
        await l2.write(entry);
        return CacheResult(
          data: networkData,
          source: CacheSource.network,
        );
      }
    } catch (e) {
      // Fallback to cache
    }

    final l1Entry = l1.getGeneric(key);
    if (l1Entry != null) {
      return CacheResult(
        data: fromJson(l1Entry.payload),
        source: CacheSource.memory,
        isStale: true,
        ageMs: l1Entry.ageMs,
      );
    }

    final l2Entry = await l2.read(key);
    if (l2Entry != null) {
      l1.setGeneric(l2Entry);
      return CacheResult(
        data: fromJson(l2Entry.payload),
        source: CacheSource.disk,
        isStale: true,
        ageMs: l2Entry.ageMs,
      );
    }

    return CacheResult(source: CacheSource.none);
  }

  Future<CacheResult<T>> _fetchCacheOnly<T>({
    required String key,
    required T Function(dynamic json) fromJson,
  }) async {
    final l1Entry = l1.getGeneric(key);
    if (l1Entry != null) {
      return CacheResult(
        data: fromJson(l1Entry.payload),
        source: CacheSource.memory,
        ageMs: l1Entry.ageMs,
      );
    }

    final l2Entry = await l2.read(key);
    if (l2Entry != null) {
      l1.setGeneric(l2Entry);
      return CacheResult(
        data: fromJson(l2Entry.payload),
        source: CacheSource.disk,
        ageMs: l2Entry.ageMs,
      );
    }

    return CacheResult(source: CacheSource.none);
  }

  Future<void> _refreshNetwork<T>({
    required String key,
    required String? userId,
    required int ttlSeconds,
    required int schemaVersion,
    required Future<T?> Function() networkFetch,
    required dynamic Function(T value) toJson,
    required String? oldHash,
    required void Function(T fresh) onRefreshed,
  }) async {
    try {
      final networkData = await networkFetch();
      if (networkData != null) {
        final payload = toJson(networkData);
        final newHash = PayloadCodec.computeHash(payload);

        final entry = CacheEntry(
          key: key,
          userId: userId,
          payload: payload,
          updatedAt: DateTime.now(),
          ttlSeconds: ttlSeconds,
          schemaVersion: schemaVersion,
          payloadHash: newHash,
        );

        l1.setGeneric(entry);
        await l2.write(entry);

        if (oldHash != newHash) {
          onRefreshed(networkData);
        }
      }
    } catch (e) {
      // Refresh failed
    }
  }

  /// Purges all cache entries for this repository (user-scoped).
  Future<void> clearUserCache(String userId) async {
    l1.purgeUserScope(userId);
    await l2.purgeUserScope(userId);
  }
}
