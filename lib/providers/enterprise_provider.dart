import 'package:flutter/material.dart';
import '../models/enterprise_models.dart';
import '../services/enterprise_service.dart';

class EnterpriseProvider with ChangeNotifier {
  final EnterpriseService _service = EnterpriseService();

  SubscriptionTier? _subscription;
  List<TeamWorkspace> _workspaces = [];
  List<Integration> _integrations = [];
  bool _isLoading = false;

  SubscriptionTier? get subscription => _subscription;
  List<TeamWorkspace> get workspaces => _workspaces;
  List<Integration> get integrations => _integrations;
  bool get isLoading => _isLoading;

  Future<void> loadEnterpriseData(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _subscription = await _service.getSubscription(userId);
      _workspaces = await _service.getWorkspaces(userId);
      _integrations = await _service.getIntegrations(userId);
    } catch (e) {
      print('Failed to load enterprise data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
