// Purpose: Batches audit_log writes in memory and flushes to Supabase every 5 s or every 10 events.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

// Batches audit_log writes in memory and flushes every 5s or every 10 events
class AnalyticsService {
  // Singleton
  AnalyticsService._internal();
  static final AnalyticsService instance = AnalyticsService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  // Batch queue
  final List<Map<String, dynamic>> _queue = [];
  Timer? _flushTimer;
  static const int _batchSize = 10;
  static const Duration _flushInterval = Duration(seconds: 5);

  void logAction({
    required String action,
    String? entityType,
    String? entityId,
    Map<String, dynamic>? details,
  }) {
    final user = AuthService.instance.currentUser;
    if (user == null) return; // Not authenticated — skip silently

    _queue.add({
      'user_id': user.id,
      'action': action,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (details != null) 'details': details,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    // Flush immediately when batch is full
    if (_queue.length >= _batchSize) {
      _flush();
    } else {
      _ensureTimer();
    }
  }

  void _ensureTimer() {
    _flushTimer ??= Timer(_flushInterval, _flush);
  }

  Future<void> _flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;

    if (_queue.isEmpty) return;

    final batch = List<Map<String, dynamic>>.from(_queue);
    _queue.clear();

    try {
      await _client.from('audit_log').insert(batch);
    } catch (e) {
      debugPrint('AnalyticsService flush error: $e');
      // Re-enqueue on failure so events aren't lost
      _queue.insertAll(0, batch);
    }
  }

  // Force-flush any pending events (call before app pauses or on logout)
  Future<void> flushNow() => _flush();

  Future<void> dispose() async {
    await _flush();
    _flushTimer?.cancel();
  }
}
