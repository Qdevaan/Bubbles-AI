import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/enterprise_models.dart';

class EnterpriseService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<SubscriptionTier?> getSubscription(String userId) async {
    try {
      final response = await _supabase
          .from('subscriptions')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response != null) {
        return SubscriptionTier.fromJson(response);
      }
      return null;
    } catch (e) {
      print('Error fetching subscription: $e');
      return null;
    }
  }

  Future<List<TeamWorkspace>> getWorkspaces(String userId) async {
    try {
      final response = await _supabase
          .from('team_members')
          .select('team_workspaces(*)')
          .eq('user_id', userId);

      return (response as List)
          .map((item) => TeamWorkspace.fromJson(item['team_workspaces']))
          .toList();
    } catch (e) {
      print('Error fetching workspaces: $e');
      return [];
    }
  }

  Future<List<Integration>> getIntegrations(String userId) async {
    try {
      final response = await _supabase
          .from('integrations')
          .select()
          .eq('user_id', userId);

      return (response as List).map((json) => Integration.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching integrations: $e');
      return [];
    }
  }
}
