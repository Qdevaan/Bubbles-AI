import 'package:flutter/foundation.dart';

import '../models/scenario_models.dart';
import '../services/api_service.dart';

enum ScenariosLoadState { idle, loading, loaded, error }

class ScenariosProvider extends ChangeNotifier {
  ScenariosProvider(this._api);

  final ApiService _api;

  List<Scenario> _suggested = const [];
  ScenariosLoadState _state = ScenariosLoadState.idle;
  String? _error;
  bool _generating = false;
  int? _lastGenerateStatus;

  List<Scenario> get suggested => _suggested;
  ScenariosLoadState get state => _state;
  String? get error => _error;
  bool get generating => _generating;
  int? get lastGenerateStatus => _lastGenerateStatus;

  Future<void> loadSuggested() async {
    _state = ScenariosLoadState.loading;
    _error = null;
    notifyListeners();
    final raw = await _api.getScenarios(status: 'suggested', limit: 30);
    if (raw == null) {
      _state = ScenariosLoadState.error;
      _error = "Couldn't load scenarios.";
      notifyListeners();
      return;
    }
    _suggested = [for (final j in raw) Scenario.fromJson(j)];
    _state = ScenariosLoadState.loaded;
    notifyListeners();
  }

  Future<Scenario?> generate({required String targetEntityId}) async {
    _generating = true;
    _lastGenerateStatus = null;
    notifyListeners();
    final res = await _api.generateScenario(targetEntityId);
    _lastGenerateStatus = res.statusCode;
    _generating = false;
    if (res.statusCode == 201 || res.statusCode == 200) {
      try {
        final s = Scenario.fromJson(res.data!);
        _suggested = [s, ..._suggested];
        notifyListeners();
        return s;
      } catch (e) {
        debugPrint('generate parse error: $e');
        notifyListeners();
        return null;
      }
    }
    notifyListeners();
    return null;
  }

  Future<StartScenarioResponse?> start(Scenario s) async {
    final res = await _api.startScenario(s.id);
    if (res.statusCode != 200 && res.statusCode != 201) return null;
    try {
      final parsed = StartScenarioResponse.fromJson(res.data!);
      // Optimistic: remove from suggested feed.
      _suggested = [
        for (final x in _suggested)
          if (x.id != s.id) x,
      ];
      notifyListeners();
      return parsed;
    } catch (e) {
      debugPrint('startScenario parse error: $e');
      return null;
    }
  }

  Future<bool> dismiss(Scenario s) async {
    final code = await _api.dismissScenario(s.id);
    if (code != 200 && code != 204) return false;
    _suggested = [
      for (final x in _suggested)
        if (x.id != s.id) x,
    ];
    notifyListeners();
    return true;
  }

  /// Polls `/v1/scenarios?status=completed` up to [maxAttempts] times.
  /// Returns the scenario when its status flips to `completed`, or null
  /// on timeout / not-found.
  Future<Scenario?> pollCompletion(
    String scenarioId, {
    Duration interval = const Duration(seconds: 2),
    int maxAttempts = 12,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      await Future<void>.delayed(interval);
      final raw = await _api.getScenarios(status: 'completed', limit: 50);
      if (raw == null) continue;
      for (final j in raw) {
        if (j['id']?.toString() == scenarioId) {
          return Scenario.fromJson(j);
        }
      }
    }
    return null;
  }
}
