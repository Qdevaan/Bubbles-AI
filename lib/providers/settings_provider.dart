import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';

/// Manages user preferences with dual persistence:
///  - SharedPreferences for offline/instant reads
///  - Supabase `user_settings` table for cross-device sync (schema_v2)
///  - Audit logging via AnalyticsService for every change
class SettingsProvider with ChangeNotifier {
  static const String _liveToneKey = 'default_live_tone';
  static const String _consultantToneKey = 'default_consultant_tone';
  static const String _alwaysPromptKey = 'always_prompt_for_tone';
  static const String _localeKey = 'app_locale';

  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  String _defaultLiveTone = 'casual';
  String _defaultConsultantTone = 'casual';
  bool _alwaysPromptForTone = false;

  bool _pushHighlights = true;
  bool _pushEvents = true;
  bool _pushWeeklyDigest = true;
  bool _pushReminders = true;

  // Synced settings (mirror user_settings schema columns)
  String _fontSize = 'medium';
  String _voiceAssistantName = 'Bubbles';
  String? _assistantVoiceId;
  double _speechRate = 1.0;
  double _pitch = 1.0;
  bool _hapticFeedback = true;
  bool _autoPlayAudio = true;
  String _transcriptionLanguage = 'en-US';
  bool _enableNsfwFilter = true;
  bool _dataSharingOptIn = false;

  String get defaultLiveTone => _defaultLiveTone;
  String get defaultConsultantTone => _defaultConsultantTone;
  bool get alwaysPromptForTone => _alwaysPromptForTone;
  bool get pushHighlights => _pushHighlights;
  bool get pushEvents => _pushEvents;
  bool get pushWeeklyDigest => _pushWeeklyDigest;
  bool get pushReminders => _pushReminders;
  String get fontSize => _fontSize;
  String get voiceAssistantName => _voiceAssistantName;
  String? get assistantVoiceId => _assistantVoiceId;
  double get speechRate => _speechRate;
  double get pitch => _pitch;
  bool get hapticFeedback => _hapticFeedback;
  bool get autoPlayAudio => _autoPlayAudio;
  String get transcriptionLanguage => _transcriptionLanguage;
  bool get enableNsfwFilter => _enableNsfwFilter;
  bool get dataSharingOptIn => _dataSharingOptIn;

  SettingsProvider() {
    _loadSettings();
  }

  // ── Load: SharedPreferences first, then Supabase overrides ────────────────
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _defaultLiveTone = prefs.getString(_liveToneKey) ?? 'casual';
    _defaultConsultantTone = prefs.getString(_consultantToneKey) ?? 'casual';
    _alwaysPromptForTone = prefs.getBool(_alwaysPromptKey) ?? false;

    _pushHighlights = prefs.getBool('push_highlights') ?? true;
    _pushEvents = prefs.getBool('push_events') ?? true;
    _pushWeeklyDigest = prefs.getBool('push_weekly_digest') ?? true;
    _pushReminders = prefs.getBool('push_reminders') ?? true;

    _fontSize = prefs.getString('font_size') ?? 'medium';
    _voiceAssistantName = prefs.getString('voice_assistant_name') ?? 'Bubbles';
    _assistantVoiceId = prefs.getString('assistant_voice_id');
    _speechRate = prefs.getDouble('speech_rate') ?? 1.0;
    _pitch = prefs.getDouble('pitch') ?? 1.0;
    _hapticFeedback = prefs.getBool('haptic_feedback') ?? true;
    _autoPlayAudio = prefs.getBool('auto_play_audio') ?? true;
    _transcriptionLanguage = prefs.getString('transcription_language') ?? 'en-US';
    _enableNsfwFilter = prefs.getBool('enable_nsfw_filter') ?? true;
    _dataSharingOptIn = prefs.getBool('data_sharing_opt_in') ?? false;

    final localeCode = prefs.getString(_localeKey) ?? 'en';
    _locale = Locale(localeCode);

    notifyListeners();

    // Overlay with remote values if available
    await _loadFromSupabase();
  }

  Future<void> _loadFromSupabase() async {
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) return;
      final row = await Supabase.instance.client
          .from('user_settings')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      if (row == null) return;

      final prefs = await SharedPreferences.getInstance();

      // Sync all schema columns to local prefs
      if (row['assistant_persona'] != null) {
        final persona = row['assistant_persona'] as String;
        _defaultLiveTone = persona;
        _defaultConsultantTone = persona;
        await prefs.setString(_liveToneKey, _defaultLiveTone);
        await prefs.setString(_consultantToneKey, _defaultConsultantTone);
      }
      if (row['font_size'] != null) {
        _fontSize = row['font_size'] as String;
        await prefs.setString('font_size', _fontSize);
      }
      if (row['voice_assistant_name'] != null) {
        _voiceAssistantName = row['voice_assistant_name'] as String;
        await prefs.setString('voice_assistant_name', _voiceAssistantName);
      }
      if (row['assistant_voice_id'] != null) {
        _assistantVoiceId = row['assistant_voice_id'] as String;
        await prefs.setString('assistant_voice_id', _assistantVoiceId!);
      }
      if (row['speech_rate'] != null) {
        _speechRate = (row['speech_rate'] as num).toDouble();
        await prefs.setDouble('speech_rate', _speechRate);
      }
      if (row['pitch'] != null) {
        _pitch = (row['pitch'] as num).toDouble();
        await prefs.setDouble('pitch', _pitch);
      }
      if (row['haptic_feedback'] != null) {
        _hapticFeedback = row['haptic_feedback'] as bool;
        await prefs.setBool('haptic_feedback', _hapticFeedback);
      }
      if (row['auto_play_audio'] != null) {
        _autoPlayAudio = row['auto_play_audio'] as bool;
        await prefs.setBool('auto_play_audio', _autoPlayAudio);
      }
      if (row['transcription_language'] != null) {
        _transcriptionLanguage = row['transcription_language'] as String;
        await prefs.setString('transcription_language', _transcriptionLanguage);
      }
      if (row['enable_nsfw_filter'] != null) {
        _enableNsfwFilter = row['enable_nsfw_filter'] as bool;
        await prefs.setBool('enable_nsfw_filter', _enableNsfwFilter);
      }
      if (row['data_sharing_opt_in'] != null) {
        _dataSharingOptIn = row['data_sharing_opt_in'] as bool;
        await prefs.setBool('data_sharing_opt_in', _dataSharingOptIn);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('SettingsProvider._loadFromSupabase: $e');
    }
  }

  // ── Upsert helper ─────────────────────────────────────────────────────────
  Future<void> _upsertUserSettings(Map<String, dynamic> updates) async {
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) return;
      await Supabase.instance.client.from('user_settings').upsert({
        'user_id': user.id,
        ...updates,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('SettingsProvider._upsertUserSettings: $e');
    }
  }

  /// Helper to log a settings change to audit_log
  void _logSettingsChange(String key, dynamic value) {
    AnalyticsService.instance.logAction(
      action: 'settings_changed',
      entityType: 'user_settings',
      details: {'key': key, 'value': value.toString()},
    );
  }

  // ── Setters ───────────────────────────────────────────────────────────────
  Future<void> setAlwaysPromptForTone(bool value) async {
    _alwaysPromptForTone = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_alwaysPromptKey, value);
    notifyListeners();
    _logSettingsChange('always_prompt_for_tone', value);
  }

  Future<void> setDefaultLiveTone(String tone) async {
    _defaultLiveTone = tone;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_liveToneKey, tone);
    notifyListeners();
    _upsertUserSettings({'assistant_persona': tone});
    _logSettingsChange('default_live_tone', tone);
  }

  Future<void> setDefaultConsultantTone(String tone) async {
    _defaultConsultantTone = tone;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_consultantToneKey, tone);
    notifyListeners();
    _upsertUserSettings({'assistant_persona': tone});
    _logSettingsChange('default_consultant_tone', tone);
  }

  Future<void> setPushHighlights(bool val) async {
    _pushHighlights = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_highlights', val);
    notifyListeners();
    _logSettingsChange('push_highlights', val);
  }

  Future<void> setPushEvents(bool val) async {
    _pushEvents = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_events', val);
    notifyListeners();
    _logSettingsChange('push_events', val);
  }

  Future<void> setPushWeeklyDigest(bool val) async {
    _pushWeeklyDigest = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_weekly_digest', val);
    notifyListeners();
    _logSettingsChange('push_weekly_digest', val);
  }

  Future<void> setPushReminders(bool val) async {
    _pushReminders = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_reminders', val);
    notifyListeners();
    _logSettingsChange('push_reminders', val);
  }

  Future<void> setFontSize(String size) async {
    _fontSize = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('font_size', size);
    notifyListeners();
    _upsertUserSettings({'font_size': size});
    _logSettingsChange('font_size', size);
  }

  Future<void> setVoiceAssistantName(String name) async {
    _voiceAssistantName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voice_assistant_name', name);
    notifyListeners();
    _upsertUserSettings({'voice_assistant_name': name});
    _logSettingsChange('voice_assistant_name', name);
  }

  Future<void> setAssistantVoiceId(String? id) async {
    _assistantVoiceId = id;
    final prefs = await SharedPreferences.getInstance();
    if (id != null) {
      await prefs.setString('assistant_voice_id', id);
    } else {
      await prefs.remove('assistant_voice_id');
    }
    notifyListeners();
    _upsertUserSettings({'assistant_voice_id': id});
    _logSettingsChange('assistant_voice_id', id);
  }

  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speech_rate', rate);
    notifyListeners();
    _upsertUserSettings({'speech_rate': rate});
    _logSettingsChange('speech_rate', rate);
  }

  Future<void> setPitch(double p) async {
    _pitch = p;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pitch', p);
    notifyListeners();
    _upsertUserSettings({'pitch': p});
    _logSettingsChange('pitch', p);
  }

  Future<void> setHapticFeedback(bool val) async {
    _hapticFeedback = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('haptic_feedback', val);
    notifyListeners();
    _upsertUserSettings({'haptic_feedback': val});
    _logSettingsChange('haptic_feedback', val);
  }

  Future<void> setAutoPlayAudio(bool val) async {
    _autoPlayAudio = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_play_audio', val);
    notifyListeners();
    _upsertUserSettings({'auto_play_audio': val});
    _logSettingsChange('auto_play_audio', val);
  }

  Future<void> setTranscriptionLanguage(String lang) async {
    _transcriptionLanguage = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('transcription_language', lang);
    notifyListeners();
    _upsertUserSettings({'transcription_language': lang});
    _logSettingsChange('transcription_language', lang);
  }

  Future<void> setEnableNsfwFilter(bool val) async {
    _enableNsfwFilter = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enable_nsfw_filter', val);
    notifyListeners();
    _upsertUserSettings({'enable_nsfw_filter': val});
    _logSettingsChange('enable_nsfw_filter', val);
  }

  Future<void> setDataSharingOptIn(bool val) async {
    _dataSharingOptIn = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('data_sharing_opt_in', val);
    notifyListeners();
    _upsertUserSettings({'data_sharing_opt_in': val});
    _logSettingsChange('data_sharing_opt_in', val);
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale.languageCode);
    notifyListeners();
    _logSettingsChange('app_locale', locale.languageCode);
  }
}
