import 'package:flutter/foundation.dart';

import '../models/dashboard_models.dart';
import '../services/api_service.dart';

enum DashboardLoadState { idle, loading, loaded, error }

class DashboardProvider extends ChangeNotifier {
  DashboardProvider(this._api);

  final ApiService _api;

  static const allowedRanges = ['30d', '90d', '365d'];

  String _range = '30d';
  DashboardResponse? _data;
  DashboardLoadState _state = DashboardLoadState.idle;
  String? _error;
  int? _lastStatusCode;

  String get range => _range;
  DashboardResponse? get data => _data;
  DashboardLoadState get state => _state;
  String? get error => _error;
  int? get lastStatusCode => _lastStatusCode;
  bool get hasData => _data != null;

  Future<void> setRange(String r) async {
    if (!allowedRanges.contains(r) || r == _range) return;
    _range = r;
    await load();
  }

  Future<void> load() async {
    _state = DashboardLoadState.loading;
    _error = null;
    notifyListeners();
    final res = await _api.getDashboard(range: _range);
    _lastStatusCode = res.statusCode;
    if (res.statusCode == 200 && res.data != null) {
      try {
        _data = DashboardResponse.fromJson(res.data!);
        _state = DashboardLoadState.loaded;
        _error = null;
      } catch (e, st) {
        debugPrint('Dashboard parse error: $e\n$st');
        _state = DashboardLoadState.error;
        _error = "Couldn't read progress data.";
      }
    } else {
      _state = DashboardLoadState.error;
      _error = switch (res.statusCode) {
        429 => 'Slow down — try again in a moment.',
        401 => 'Session expired — please sign in again.',
        400 => 'Bad request — unsupported range.',
        _ => "Couldn't load progress — try again.",
      };
    }
    notifyListeners();
  }

  Future<void> refreshAfterSession({
    Duration delay = const Duration(seconds: 3),
  }) async {
    await Future<void>.delayed(delay);
    await load();
  }
}
