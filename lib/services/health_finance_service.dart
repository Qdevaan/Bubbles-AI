import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/health_finance_models.dart';

class HealthFinanceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<HealthMetric>> getHealthMetrics(String userId) async {
    try {
      final response = await _supabase
          .from('health_metrics')
          .select()
          .eq('user_id', userId)
          .order('recorded_at', ascending: false);

      return (response as List).map((json) => HealthMetric.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching health metrics: $e');
      return [];
    }
  }

  Future<void> addHealthMetric(HealthMetric metric) async {
    try {
      await _supabase.from('health_metrics').insert(metric.toJson());
    } catch (e) {
      print('Error adding health metric: $e');
      rethrow;
    }
  }

  Future<List<Expense>> getExpenses(String userId) async {
    try {
      final response = await _supabase
          .from('expenses')
          .select()
          .eq('user_id', userId)
          .order('date', ascending: false);

      return (response as List).map((json) => Expense.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching expenses: $e');
      return [];
    }
  }

  Future<void> addExpense(Expense expense) async {
    try {
      await _supabase.from('expenses').insert(expense.toJson());
    } catch (e) {
      print('Error adding expense: $e');
      rethrow;
    }
  }
}
