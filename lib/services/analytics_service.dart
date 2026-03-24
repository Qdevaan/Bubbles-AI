import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

/// Central analytics service that writes to the `audit_log` table in Supabase.
///
/// Provides fire-and-forget [logAction] calls. Events are batched in memory
/// and flushed periodically (every 5 s) or when the batch reaches 10 events,
/// whichever comes first. This avoids spamming the database on rapid actions.
class AnalyticsService {
  // ── Singleton ──
  AnalyticsService._internal();
  static final AnalyticsService instance = AnalyticsService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  // ── Batch queue ──
  final List<Map<String, dynamic>> _queue = [];
  Timer? _flushTimer;
  static const int _batchSize = 10;
  static const Duration _flushInterval = Duration(seconds: 5);

  /// Log a user action to the `audit_log` table.
  ///
  /// * [action] — e.g. `screen_view`, `settings_changed`, `session_started`
  /// * [entityType] — e.g. `session`, `profile`, `settings`, `notification`
  /// * [entityId] — optional UUID of the entity acted upon
  /// * [details] — arbitrary JSON payload for additional context
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

  /// Force-flush any pending events (call on app pause / logout).
  Future<void> flushNow() => _flush();

  /// Dispose: flush remaining events and cancel the timer.
  Future<void> dispose() async {
    await _flush();
    _flushTimer?.cancel();
  }
}
