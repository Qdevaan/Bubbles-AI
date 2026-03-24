import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/iot_models.dart';

class IoTManagerService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<IoTDevice>> getDevices(String userId) async {
    try {
      final response = await _supabase
          .from('iot_devices')
          .select()
          .eq('user_id', userId)
          .order('last_synced_at', ascending: false);

      return (response as List).map((json) => IoTDevice.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching IoT devices: $e');
      return [];
    }
  }

  Future<void> updateDeviceState(String deviceId, Map<String, dynamic> state) async {
    try {
      await _supabase
          .from('iot_devices')
          .update({'state': state, 'last_synced_at': DateTime.now().toIso8601String()})
          .eq('id', deviceId);
    } catch (e) {
      print('Error updating device state: $e');
      rethrow;
    }
  }
}
