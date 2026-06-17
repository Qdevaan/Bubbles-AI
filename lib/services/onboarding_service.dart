// Purpose: Reads and writes the user's onboarding completion flags so the app knows which setup steps are still pending.
import 'package:shared_preferences/shared_preferences.dart';

import 'boot_state_service.dart';

/// Tracks whether the first-launch onboarding carousel has been seen.
///
/// Bumping [_version] forces every user back through onboarding on the next
/// launch — useful when a major feature lands and the carousel is rewritten.
class OnboardingService {
  OnboardingService._();
  static final OnboardingService instance = OnboardingService._();

  static const String _key = 'onboarding_seen_v';
  static const int _version = 1;

  String get _storageKey => '$_key$_version';

  Future<bool> hasSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_storageKey) ?? false;
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_storageKey, true);
    await BootStateService.instance.setOnboardingSeen(true);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await BootStateService.instance.setOnboardingSeen(false);
  }
}
