import 'package:flutter/material.dart';
import '../models/health_finance_models.dart';
import '../services/health_finance_service.dart';

class HealthFinanceProvider with ChangeNotifier {
  final HealthFinanceService _service = HealthFinanceService();

  List<HealthMetric> _metrics = [];
  List<Expense> _expenses = [];
  bool _isLoading = false;

  List<HealthMetric> get metrics => _metrics;
  List<Expense> get expenses => _expenses;
  bool get isLoading => _isLoading;

  Future<void> loadData(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _metrics = await _service.getHealthMetrics(userId);
      _expenses = await _service.getExpenses(userId);
    } catch (e) {
      print('Failed to load health/finance data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addHealthMetric(HealthMetric metric) async {
    await _service.addHealthMetric(metric);
    _metrics.insert(0, metric);
    notifyListeners();
  }

  Future<void> addExpense(Expense expense) async {
    await _service.addExpense(expense);
    _expenses.insert(0, expense);
    notifyListeners();
  }
}
