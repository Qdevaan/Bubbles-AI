import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';

/// Dedicated state manager for the HomeScreen.
/// Fetches events, highlights and notifications; subscribes to Realtime
/// inserts on both the `highlights` and `notifications` tables (schema_v2).
class HomeProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? get profile => _profile;

  bool _loading = true;
  bool get loading => _loading;

  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> get events => List.unmodifiable(_events);

  List<Map<String, dynamic>> _highlights = [];
  List<Map<String, dynamic>> get highlights => List.unmodifiable(_highlights);

  // notifications (schema_v2 F1)
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> get notifications => List.unmodifiable(_notifications);

  bool _insightsLoaded = false;
  bool get insightsLoaded => _insightsLoaded;

  int _unreadNotifications = 0;
  int get unreadNotifications => _unreadNotifications;

  RealtimeChannel? _highlightsChannel;
  RealtimeChannel? _notificationsChannel;

  void init() {
    loadProfile();
    loadInsights();
    subscribeToHighlights();
    _subscribeToNotifications();
  }

  void clearUnread() {
    _unreadNotifications = 0;
    notifyListeners();
  }

  Future<void> clearAllHighlights() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    await _supabase
        .from('highlights')
        .update({'is_dismissed': true})
        .eq('user_id', user.id)
        .eq('is_dismissed', false);
    final count = _highlights.length;
    _highlights.clear();
    notifyListeners();
    AnalyticsService.instance.logAction(
      action: 'highlights_cleared',
      entityType: 'highlight',
      details: {'count': count},
    );
  }

  // ── Mark a notification as read ──────────────────────────────────────────
  Future<void> markNotificationRead(String notifId) async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notifId);
      _notifications.removeWhere((n) => n['id'] == notifId);
      notifyListeners();
      AnalyticsService.instance.logAction(
        action: 'notification_read',
        entityType: 'notification',
        entityId: notifId,
      );
    } catch (e) {
      debugPrint('markNotificationRead error: $e');
    }
  }

  // ── Realtime: highlights ──────────────────────────────────────────────────
  void subscribeToHighlights() {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    _highlightsChannel = _supabase
        .channel('home_highlights_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'highlights',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            final record = Map<String, dynamic>.from(payload.newRecord);
            _highlights.insert(0, record);
            _unreadNotifications++;
            notifyListeners();
          },
        )
        .subscribe();
  }

  // ── Realtime: notifications (schema_v2) ───────────────────────────────────
  void _subscribeToNotifications() {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    _notificationsChannel = _supabase
        .channel('home_notifications_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            final record = Map<String, dynamic>.from(payload.newRecord);
            _notifications.insert(0, record);
            _unreadNotifications++;
            notifyListeners();
          },
        )
        .subscribe();
  }

  Future<void> loadProfile() async {
    final data = await AuthService.instance.getProfile();
    _profile = data;
    _loading = false;
    notifyListeners();
  }

  Future<void> loadInsights() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    try {
      final eventsRes = await _supabase
          .from('events')
          .select('title, due_text, description, created_at')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(5);

      final highlightsRes = await _supabase
          .from('highlights')
          .select('title, body, highlight_type, created_at')
          .eq('user_id', user.id)
          .eq('is_resolved', false)
          .order('created_at', ascending: false)
          .limit(5);

      // Load unread notifications
      final notifRes = await _supabase
          .from('notifications')
          .select('id, title, body, notif_type, is_read, created_at')
          .eq('user_id', user.id)
          .eq('is_read', false)
          .order('created_at', ascending: false)
          .limit(20);

      _events = List<Map<String, dynamic>>.from(eventsRes);
      _highlights = List<Map<String, dynamic>>.from(highlightsRes);
      _notifications = List<Map<String, dynamic>>.from(notifRes);
      _insightsLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading insights: $e');
      _insightsLoaded = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _highlightsChannel?.unsubscribe();
    _notificationsChannel?.unsubscribe();
    super.dispose();
  }
}
