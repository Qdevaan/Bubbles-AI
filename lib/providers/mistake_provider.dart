import 'package:flutter/foundation.dart';

import '../services/mistake_service.dart';
import '../services/suggestion_service.dart' show CancelToken;

class MistakeProvider extends ChangeNotifier {
  final MistakeService service;
  bool _inFlight = false;
  int _sessionTotal = 0;
  final Map<String, int> _byCategory = {};
  final List<MistakeItem> _items = [];

  MistakeProvider({required this.service});

  int get sessionTotal => _sessionTotal;
  Map<String, int> get byCategory => Map.unmodifiable(_byCategory);
  List<MistakeItem> get items => List.unmodifiable(_items);
  bool get inFlight => _inFlight;

  Future<void> onUserTurnFinal(
    String userId,
    String sessionId,
    String transcript,
  ) async {
    if (_inFlight) return; // coalesce overlapping calls
    if (transcript.trim().isEmpty) return;
    _inFlight = true;
    notifyListeners();
    try {
      final res = await service.checkTurn(
        userId: userId,
        sessionId: sessionId,
        transcript: transcript,
        cancelToken: CancelToken(),
      );
      if (res != null && res.items.isNotEmpty) {
        _sessionTotal += res.count;
        for (final it in res.items) {
          _byCategory[it.category] = (_byCategory[it.category] ?? 0) + 1;
          _items.add(it);
        }
      }
    } finally {
      _inFlight = false;
      notifyListeners();
    }
  }

  void clear() {
    _sessionTotal = 0;
    _byCategory.clear();
    _items.clear();
    _inFlight = false;
    notifyListeners();
  }
}
