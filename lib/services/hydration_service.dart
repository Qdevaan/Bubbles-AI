import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/profile_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/home_repository.dart';
import '../repositories/insights_repository.dart';
import '../repositories/graph_repository.dart';
import '../repositories/entity_repository.dart';
import '../repositories/gamification_repository.dart';
import '../repositories/sessions_repository.dart';
import 'connection_service.dart';

class HydrationService with ChangeNotifier {
  final ConnectionService _connection;
  final ProfileRepository _profile;
  final SettingsRepository _settings;
  final HomeRepository _home;
  final InsightsRepository _insights;
  final GraphRepository _graph;
  final EntityRepository _entity;
  final GamificationRepository _gamification;
  final SessionsRepository _sessions;

  String? _userId;
  ConnectionStatus _lastStatus = ConnectionStatus.disconnected;
  final List<StreamSubscription<dynamic>> _realtimeSubs = [];

  HydrationService({
    required ConnectionService connection,
    required ProfileRepository profile,
    required SettingsRepository settings,
    required HomeRepository home,
    required InsightsRepository insights,
    required GraphRepository graph,
    required EntityRepository entity,
    required GamificationRepository gamification,
    required SessionsRepository sessions,
  })  : _connection = connection,
        _profile = profile,
        _settings = settings,
        _home = home,
        _insights = insights,
        _graph = graph,
        _entity = entity,
        _gamification = gamification,
        _sessions = sessions {
    _connection.addListener(_onConnectionChanged);
  }

  /// Called on login. Triggers initial hydration and Realtime subscriptions.
  void setUserId(String userId) {
    _userId = userId;
    refreshAll(userId);
    _initRealtime(userId);
  }

  /// Called on logout. Cancels Realtime subscriptions.
  void clearUserId() {
    _userId = null;
    _cancelRealtime();
  }

  /// Force-refresh all repositories in parallel.
  Future<void> refreshAll(String userId) async {
    await Future.wait<dynamic>([
      _profile.getProfile(userId, forceRefresh: true),
      _settings.loadSettings(userId),
      _home.getEvents(userId, forceRefresh: true),
      _home.getHighlights(userId, forceRefresh: true),
      _home.getNotifications(userId, forceRefresh: true),
      _insights.getEvents(userId, forceRefresh: true),
      _insights.getHighlights(userId, forceRefresh: true),
      _insights.getNotifications(userId, forceRefresh: true),
      _graph.getGraphExport(userId, forceRefresh: true),
      _entity.getEntities(userId, forceRefresh: true),
      _gamification.getGamification(userId, forceRefresh: true),
      _gamification.getQuests(userId, forceRefresh: true),
      _sessions.getConsultantSessions(userId, forceRefresh: true),
    ]);
  }

  void _onConnectionChanged() {
    final newStatus = _connection.status;
    final wasDisconnected = _lastStatus != ConnectionStatus.connected;
    if (newStatus == ConnectionStatus.connected && wasDisconnected && _userId != null) {
      refreshAll(_userId!);
    }
    _lastStatus = newStatus;
  }

  void _initRealtime(String userId) {
    _cancelRealtime();
    final client = Supabase.instance.client;

    // gamification XP/streak changes → refresh gamification cache
    _realtimeSubs.add(
      client
          .from('user_gamification')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .listen((_) => _gamification.getGamification(userId, forceRefresh: true)),
    );

    // new entities extracted by server → refresh entity cache
    _realtimeSubs.add(
      client
          .from('entities')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .listen((_) => _entity.getEntities(userId, forceRefresh: true)),
    );

    // new session saved → refresh sessions list
    _realtimeSubs.add(
      client
          .from('sessions')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .listen((_) => _sessions.getConsultantSessions(userId, forceRefresh: true)),
    );
  }

  void _cancelRealtime() {
    for (final sub in _realtimeSubs) {
      sub.cancel();
    }
    _realtimeSubs.clear();
  }

  @override
  void dispose() {
    _connection.removeListener(_onConnectionChanged);
    _cancelRealtime();
    super.dispose();
  }
}
