import 'package:flutter/foundation.dart';
import '../models/performa.dart';
import '../repositories/performa_repository.dart';

class PerformaProvider extends ChangeNotifier {
  final PerformaRepository _repo;

  Performa? _performa;
  bool _isLoading = false;
  String? _error;

  Performa? get performa => _performa;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasPendingInsights => _performa?.pendingInsights.isNotEmpty ?? false;

  PerformaProvider(this._repo);

  Future<void> load(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _performa = await _repo.fetch(userId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> save(String userId, Performa updated) async {
    await _repo.save(userId, updated);
    _performa = updated;
    notifyListeners();
  }

  Future<void> approveInsight(String userId, String insightId) async {
    await _repo.approveInsight(userId, insightId, true);
    notifyListeners();
  }

  Future<void> rejectInsight(String userId, String insightId) async {
    await _repo.approveInsight(userId, insightId, false);
    if (_performa != null) {
      final updated = _performa!.aiInsights.where((i) => i.id != insightId).toList();
      _performa = _performa!.copyWith(aiInsights: updated);
    }
    notifyListeners();
  }
}
