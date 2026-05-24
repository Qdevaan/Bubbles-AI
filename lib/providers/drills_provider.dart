import 'package:flutter/foundation.dart';

import '../models/drill_models.dart';
import '../services/api_service.dart';

enum DrillsLoadState { idle, loading, loaded, error }

class DrillsProvider extends ChangeNotifier {
  DrillsProvider(this._api);

  final ApiService _api;

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

  Future<void> load({bool includeUpcomingFallback = true}) async {
    _state = DrillsLoadState.loading;
    _error = null;
    notifyListeners();
    final due = await _api.getDrillsQueue(limit: 50);
    if (due == null) {
      _state = DrillsLoadState.error;
      _error = 'Could not load drills.';
      notifyListeners();
      return;
    }
    var parsed = DrillQueueResponse.fromJson(due);

    if (parsed.cards.isEmpty && includeUpcomingFallback) {
      final upcoming = await _api.getDrillsQueue(
        limit: 20,
        includeUpcoming: true,
      );
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

  /// Returns the review response (with xpAwarded) on success, null on
  /// failure. `statusCode` is exposed via the `lastReviewError` getter
  /// for caller toast handling.
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
    notifyListeners();
    return true;
  }

  /// Wait 2-5 s after `end_session`, then refresh once so worker-
  /// materialised cards show up.
  Future<void> refreshAfterSession({
    Duration delay = const Duration(seconds: 3),
  }) async {
    await Future<void>.delayed(delay);
    await load();
  }
}
