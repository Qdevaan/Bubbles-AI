// Purpose: State manager for the spaced-repetition drills feature — loads the card queue and submits reviews.
import 'package:flutter/foundation.dart';

import '../models/drill_models.dart';
import '../repositories/drills_repository.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

enum DrillsLoadState { idle, loading, loaded, error }

class DrillsProvider extends ChangeNotifier {
  DrillsProvider(this._api);

  final ApiService _api;
  DrillsRepository? _repo;
  void setRepository(DrillsRepository repo) => _repo = repo;

  List<DrillCard> _cards = const [];
  int _totalDue = 0;
  bool _isUpcoming = false;
  DrillsLoadState _state = DrillsLoadState.idle;
  String? _error;
  bool _includeUpcoming = false;

  List<DrillCard> get cards => _cards;
  int get totalDue => _totalDue;
  bool get isUpcoming => _isUpcoming;
  DrillsLoadState get state => _state;
  String? get error => _error;
  bool get includeUpcoming => _includeUpcoming;
  int get badgeCount => _totalDue;
  bool get hasData => _state == DrillsLoadState.loaded;

  Future<void> load({
    bool includeUpcomingFallback = true,
    bool forceRefresh = false,
  }) async {
    _state = DrillsLoadState.loading;
    _error = null;
    notifyListeners();

    final userId = AuthService.instance.currentUser?.id;

    Future<Map<String, dynamic>?> fetchDue() async {
      if (_repo != null && userId != null) {
        final result = await _repo!.getQueue(
          userId: userId,
          limit: 50,
          forceRefresh: forceRefresh,
        );
        return result.data;
      }
      return _api.getDrillsQueue(limit: 50);
    }

    Future<Map<String, dynamic>?> fetchUpcoming() async {
      if (_repo != null && userId != null) {
        final result = await _repo!.getQueue(
          userId: userId,
          limit: 20,
          includeUpcoming: true,
          forceRefresh: forceRefresh,
        );
        return result.data;
      }
      return _api.getDrillsQueue(limit: 20, includeUpcoming: true);
    }

    final due = await fetchDue();
    if (due == null) {
      _state = DrillsLoadState.error;
      _error = 'Could not load drills.';
      notifyListeners();
      return;
    }
    var parsed = DrillQueueResponse.fromJson(due);

    if (parsed.cards.isEmpty && includeUpcomingFallback) {
      final upcoming = await fetchUpcoming();
      if (upcoming != null) {
        final fallback = DrillQueueResponse.fromJson(upcoming);
        if (fallback.cards.isNotEmpty) {
          parsed = DrillQueueResponse(
            cards: fallback.cards,
            totalDue: parsed.totalDue, // still 0 due — surface that
            isUpcoming: true,
          );
        }
      }
    }

    _cards = parsed.cards;
    _totalDue = parsed.totalDue;
    _isUpcoming = parsed.isUpcoming;
    _includeUpcoming = parsed.isUpcoming;
    _state = DrillsLoadState.loaded;
    notifyListeners();
  }

  // statusCode of the last failed review — caller reads this to show a toast
  int? _lastReviewError;
  int? get lastReviewError => _lastReviewError;

  Future<ReviewDrillResponse?> review(
    DrillCard card, {
    required DrillResult result,
  }) async {
    _lastReviewError = null;
    final res = await _api.reviewDrill(
      cardId: card.id,
      result: result == DrillResult.correct ? 'correct' : 'wrong',
    );
    if (res.statusCode != 200 || res.data == null) {
      _lastReviewError = res.statusCode;
      notifyListeners();
      return null;
    }
    final parsed = ReviewDrillResponse.fromJson(res.data!);
    // Optimistic update: remove the card from the stack (server has
    // moved its due_at forward — it's not due now).
    _cards = [
      for (final c in _cards)
        if (c.id != card.id) c,
    ];
    // total_due was decremented by the server; reflect that locally.
    if (_totalDue > 0) _totalDue -= 1;
    await _invalidateQueueCache();
    notifyListeners();
    return parsed;
  }

  Future<bool> retire(DrillCard card) async {
    final res = await _api.retireDrill(card.id);
    if (res.statusCode != 200) return false;
    _cards = [
      for (final c in _cards)
        if (c.id != card.id) c,
    ];
    if (_totalDue > 0 && !card.isMastered) _totalDue -= 1;
    await _invalidateQueueCache();
    notifyListeners();
    return true;
  }

  Future<void> _invalidateQueueCache() async {
    final userId = AuthService.instance.currentUser?.id;
    if (_repo == null || userId == null) return;
    await _repo!.invalidateQueue(userId);
  }

  // Give the server a moment to materialise new cards after a session ends
  Future<void> refreshAfterSession({
    Duration delay = const Duration(seconds: 3),
  }) async {
    await Future<void>.delayed(delay);
    await load();
  }
}
