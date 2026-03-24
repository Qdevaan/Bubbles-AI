import 'package:flutter/material.dart';
import '../models/core_identity.dart';
import '../services/identity_service.dart';

class ProfileProvider with ChangeNotifier {
  final IdentityService _identityService = IdentityService();
  
  Profile? _profile;
  UserSettings? _settings;
  bool _isLoading = false;

  Profile? get profile => _profile;
  UserSettings? get settings => _settings;
  bool get isLoading => _isLoading;

  Future<void> loadIdentityData(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _profile = await _identityService.getProfile(userId);
      _settings = await _identityService.getUserSettings(userId);
    } catch (e) {
      print('Failed to load identity data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateProfile(Profile updatedProfile) async {
    await _identityService.updateProfile(updatedProfile);
    _profile = updatedProfile;
    notifyListeners();
  }

  Future<void> updateSettings(UserSettings updatedSettings) async {
    await _identityService.updateUserSettings(updatedSettings);
    _settings = updatedSettings;
    notifyListeners();
  }
}
