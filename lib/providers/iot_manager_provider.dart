import 'package:flutter/material.dart';
import '../models/iot_models.dart';
import '../services/iot_manager_service.dart';

class IoTManagerProvider with ChangeNotifier {
  final IoTManagerService _service = IoTManagerService();

  List<IoTDevice> _devices = [];
  bool _isLoading = false;

  List<IoTDevice> get devices => _devices;
  bool get isLoading => _isLoading;

  Future<void> loadDevices(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _devices = await _service.getDevices(userId);
    } catch (e) {
      print('Failed to load IoT devices: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleDeviceState(IoTDevice device, bool newState) async {
    // Optimistic update locally
    final updatedState = Map<String, dynamic>.from(device.state ?? {});
    updatedState['power'] = newState ? 'on' : 'off';
    
    // Call service to update backend later
    await _service.updateDeviceState(device.id, updatedState);
  }
}
