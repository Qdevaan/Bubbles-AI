import 'package:shared_preferences/shared_preferences.dart';

import 'boot_state_service.dart';

/// Tracks whether the user explicitly skipped the Performa setup wizard.
///
/// When skipped, [AuthGate] / [AppBootstrap] lets the user reach Home without
/// a persona row instead of blocking them on the wizard. The flag is cleared
/// automatically whenever a persona is upserted.
class PersonaSkipService {
  PersonaSkipService._();
  static final PersonaSkipService instance = PersonaSkipService._();

  static const String _key = 'persona_skipped_v1';

  Future<bool> isSkipped() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> markSkipped() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    await BootStateService.instance.setPersonaSkipped(true);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await BootStateService.instance.setPersonaSkipped(false);
  }
}
