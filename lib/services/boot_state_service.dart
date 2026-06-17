// Purpose: Reads and writes the persisted boot-state (theme, surface style) so AppBootstrap can route on the first frame.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Synchronous mirror of boot-critical flags persisted in SharedPreferences.
///
/// [AppBootstrap] consults this mirror on the first frame to decide which
/// screen to mount without waiting on any async work. Providers write through
/// to the mirror whenever their state changes so the next cold start reads a
/// fresh value.
///
/// Keys are versioned (`_v1`) so a schema bump can invalidate stale mirrors.
class BootStateService {
  BootStateService._();
  static final BootStateService instance = BootStateService._();

  static const String _personaCompleteKey = 'boot_persona_complete_v1';
  static const String _personaSkippedKey = 'persona_skipped_v1';
  static const String _onboardingSeenKey = 'onboarding_seen_v1';
  static const String _lastUserIdKey = 'boot_last_user_id_v1';
  static const String _themeModeKey = 'theme_mode_pref';
  static const String _seedColorKey = 'theme_seed_color';
  static const String _surfaceStyleKey = 'boot_surface_style_v1';
  static const String _perfTierKey = 'boot_perf_tier_v1';

  SharedPreferences? _prefs;

  bool _personaComplete = false;
  bool _personaSkipped = false;
  bool _onboardingSeen = false;
  String? _lastUserId;
  ThemeMode _themeMode = ThemeMode.system;
  Color? _seedColor;
  String? _surfaceStyle;
  String? _perfTier;

  bool get personaComplete => _personaComplete;
  bool get personaSkipped => _personaSkipped;
  bool get onboardingSeen => _onboardingSeen;
  String? get lastUserId => _lastUserId;
  ThemeMode get themeMode => _themeMode;
  Color? get seedColor => _seedColor;
  String? get surfaceStyle => _surfaceStyle;
  String? get perfTier => _perfTier;

  /// True when the persona is either completed or explicitly skipped — the
  /// app may proceed to the home screen.
  bool get canSkipWizard => _personaComplete || _personaSkipped;

  /// Loads the mirror once during app startup. Subsequent calls are cheap.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _personaComplete = prefs.getBool(_personaCompleteKey) ?? false;
    _personaSkipped = prefs.getBool(_personaSkippedKey) ?? false;
    _lastUserId = prefs.getString(_lastUserIdKey);

    // Resolve onboarding key against the active version (matches OnboardingService).
    final onboardingActiveKey = '${_onboardingSeenKey}1';
    _onboardingSeen = prefs.getBool(onboardingActiveKey) ?? false;

    final savedMode = prefs.getInt(_themeModeKey);
    if (savedMode != null &&
        savedMode >= 0 &&
        savedMode < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[savedMode];
    }
    final savedColor = prefs.getInt(_seedColorKey);
    if (savedColor != null) _seedColor = Color(savedColor);

    _surfaceStyle = prefs.getString(_surfaceStyleKey);
    _perfTier = prefs.getString(_perfTierKey);
  }

  Future<void> setPersonaComplete(bool value) async {
    _personaComplete = value;
    await _prefs?.setBool(_personaCompleteKey, value);
  }

  Future<void> setPersonaSkipped(bool value) async {
    _personaSkipped = value;
    await _prefs?.setBool(_personaSkippedKey, value);
  }

  Future<void> setOnboardingSeen(bool value) async {
    _onboardingSeen = value;
    await _prefs?.setBool('${_onboardingSeenKey}1', value);
  }

  Future<void> setLastUserId(String? value) async {
    _lastUserId = value;
    if (value == null) {
      await _prefs?.remove(_lastUserIdKey);
    } else {
      await _prefs?.setString(_lastUserIdKey, value);
    }
  }

  Future<void> setSurfaceStyle(String value) async {
    _surfaceStyle = value;
    await _prefs?.setString(_surfaceStyleKey, value);
  }

  Future<void> setPerfTier(String value) async {
    _perfTier = value;
    await _prefs?.setString(_perfTierKey, value);
  }

  /// Cleared on sign-out so the next launch starts from a cold cache.
  Future<void> clearUserScope() async {
    _personaComplete = false;
    _personaSkipped = false;
    _lastUserId = null;
    await _prefs?.remove(_personaCompleteKey);
    await _prefs?.remove(_personaSkippedKey);
    await _prefs?.remove(_lastUserIdKey);
  }
}
