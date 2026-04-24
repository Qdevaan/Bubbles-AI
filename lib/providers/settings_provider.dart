import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../repositories/settings_repository.dart';

/// Manages user preferences with dual persistence:
///  - SharedPreferences for offline/instant reads
///  - Supabase `user_settings` table for cross-device sync (schema_v2)
///  - Audit logging via AnalyticsService for every change
class SettingsProvider with ChangeNotifier {
  static const String _liveToneKey = 'default_live_tone';
  static const String _consultantToneKey = 'default_consultant_tone';
  static const String _alwaysPromptKey = 'always_prompt_for_tone';
  static const String _localeKey = 'app_locale';
  static const String _quickActionsStyleKey = 'quick_actions_style';
  static const String _enabledQuickActionsKey = 'enabled_quick_actions';

  SettingsRepository? _repository;
  void setRepository(SettingsRepository repo) => _repository = repo;

  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  String _defaultLiveTone = 'casual';
  String _defaultConsultantTone = 'casual';
  bool _alwaysPromptForTone = false;
  String _quickActionsStyle = 'grid'; // 'list', 'grid', or 'icons'
  List<String> _enabledQuickActions = ['consultant', 'sessions', 'roleplay', 'game-center', 'graph-explorer', 'insights'];

  bool _pushHighlights = true;
  bool _pushEvents = true;
  bool _pushWeeklyDigest = true;
  bool _pushReminders = true;
  bool _pushAnnouncements = true;

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
  String get quickActionsStyle => _quickActionsStyle;
  List<String> get enabledQuickActions => _enabledQuickActions;
  bool get pushHighlights => _pushHighlights;
  bool get pushEvents => _pushEvents;
  bool get pushWeeklyDigest => _pushWeeklyDigest;
  bool get pushReminders => _pushReminders;
  bool get pushAnnouncements => _pushAnnouncements;
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
    loadSettings();
  }

  // ── Load: SharedPreferences first, then Supabase overrides ────────────────
  Future<void> loadSettings() async {
    final user = AuthService.instance.currentUser;
    
    // Repository-first approach (Offline-first with SWR)
    if (user != null && _repository != null) {
      final settings = await _repository!.loadSettings(user.id);
      _applySettingsMap(settings);
    } else {
      // Fallback for Guest mode or initialization before repository is ready
      final prefs = await SharedPreferences.getInstance();
      _defaultLiveTone = prefs.getString(_liveToneKey) ?? 'casual';
      if (_defaultLiveTone == 'serious') _defaultLiveTone = 'formal';
      _defaultConsultantTone = prefs.getString(_consultantToneKey) ?? 'casual';
      if (_defaultConsultantTone == 'serious') _defaultConsultantTone = 'formal';
      _alwaysPromptForTone = prefs.getBool(_alwaysPromptKey) ?? true;
      _quickActionsStyle = prefs.getString(_quickActionsStyleKey) ?? 'grid';
      final list = prefs.getStringList(_enabledQuickActionsKey);
      if (list != null) _enabledQuickActions = list;

      _pushHighlights = prefs.getBool('push_highlights') ?? true;
      _pushEvents = prefs.getBool('push_events') ?? true;
      _pushWeeklyDigest = prefs.getBool('push_weekly_digest') ?? true;
      _pushReminders = prefs.getBool('push_reminders') ?? true;
      _pushAnnouncements = prefs.getBool('push_announcements') ?? true;

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
    }

    notifyListeners();
  }

  void _applySettingsMap(Map<String, dynamic> settings) {
    if (settings['assistant_persona'] != null) {
      String persona = settings['assistant_persona'] as String;
      if (persona == 'serious') persona = 'formal';
      _defaultLiveTone = persona;
      _defaultConsultantTone = persona;
    }
    if (settings['font_size'] != null) _fontSize = settings['font_size'];
    if (settings['voice_assistant_name'] != null) _voiceAssistantName = settings['voice_assistant_name'];
    if (settings['assistant_voice_id'] != null) _assistantVoiceId = settings['assistant_voice_id'];
    if (settings['speech_rate'] != null) _speechRate = (settings['speech_rate'] as num).toDouble();
    if (settings['pitch'] != null) _pitch = (settings['pitch'] as num).toDouble();
    if (settings['haptic_feedback'] != null) _hapticFeedback = settings['haptic_feedback'];
    if (settings['auto_play_audio'] != null) _autoPlayAudio = settings['auto_play_audio'];
    if (settings['transcription_language'] != null) _transcriptionLanguage = settings['transcription_language'];
    if (settings['enable_nsfw_filter'] != null) _enableNsfwFilter = settings['enable_nsfw_filter'];
    if (settings['data_sharing_opt_in'] != null) _dataSharingOptIn = settings['data_sharing_opt_in'];
    
    // Non-synced/local only
    if (settings[_alwaysPromptKey] != null) _alwaysPromptForTone = settings[_alwaysPromptKey];
    if (settings[_quickActionsStyleKey] != null) _quickActionsStyle = settings[_quickActionsStyleKey];
    if (settings[_enabledQuickActionsKey] != null) _enabledQuickActions = List<String>.from(settings[_enabledQuickActionsKey]);
    if (settings[_localeKey] != null) _locale = Locale(settings[_localeKey]);
    
    if (settings['push_highlights'] != null) _pushHighlights = settings['push_highlights'];
    if (settings['push_events'] != null) _pushEvents = settings['push_events'];
    if (settings['push_weekly_digest'] != null) _pushWeeklyDigest = settings['push_weekly_digest'];
    if (settings['push_reminders'] != null) _pushReminders = settings['push_reminders'];
    if (settings['push_announcements'] != null) _pushAnnouncements = settings['push_announcements'];
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

      final Map<String, dynamic> updates = {};
      if (row['assistant_persona'] != null) updates['assistant_persona'] = row['assistant_persona'];
      if (row['font_size'] != null) updates['font_size'] = row['font_size'];
      if (row['voice_assistant_name'] != null) updates['voice_assistant_name'] = row['voice_assistant_name'];
      if (row['assistant_voice_id'] != null) updates['assistant_voice_id'] = row['assistant_voice_id'];
      if (row['speech_rate'] != null) updates['speech_rate'] = row['speech_rate'];
      if (row['pitch'] != null) updates['pitch'] = row['pitch'];
      if (row['haptic_feedback'] != null) updates['haptic_feedback'] = row['haptic_feedback'];
      if (row['auto_play_audio'] != null) updates['auto_play_audio'] = row['auto_play_audio'];
      if (row['transcription_language'] != null) updates['transcription_language'] = row['transcription_language'];
      if (row['enable_nsfw_filter'] != null) updates['enable_nsfw_filter'] = row['enable_nsfw_filter'];
      if (row['data_sharing_opt_in'] != null) updates['data_sharing_opt_in'] = row['data_sharing_opt_in'];

      _applySettingsMap(updates);
      notifyListeners();
    } catch (e) {
      debugPrint('SettingsProvider._loadFromSupabase: $e');
    }
  }

  // ── Write helper ──────────────────────────────────────────────────────────
  Future<void> _updateSetting(String key, dynamic value, {Map<String, dynamic>? remoteUpdates}) async {
    final user = AuthService.instance.currentUser;
    if (user != null && _repository != null) {
      await _repository!.writeSetting(user.id, key, value);
      if (remoteUpdates != null) {
        await _upsertUserSettings(remoteUpdates);
      }
    } else {
      // Offline/Guest fallback
      final prefs = await SharedPreferences.getInstance();
      if (value is bool) await prefs.setBool(key, value);
      else if (value is String) await prefs.setString(key, value);
      else if (value is double) await prefs.setDouble(key, value);
      if (remoteUpdates != null) await _upsertUserSettings(remoteUpdates);
    }
    notifyListeners();
    _logSettingsChange(key, value);
  }

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
    await _updateSetting(_alwaysPromptKey, value);
  }

  Future<void> setQuickActionsStyle(String style) async {
    _quickActionsStyle = style;
    await _updateSetting(_quickActionsStyleKey, style);
  }

  Future<void> setEnabledQuickActions(List<String> actions) async {
    _enabledQuickActions = actions;
    // Persist locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_enabledQuickActionsKey, actions);
    if (_repository != null) {
      final user = AuthService.instance.currentUser;
      if (user != null) await _repository!.writeSetting(user.id, _enabledQuickActionsKey, actions);
    }
    notifyListeners();
  }

  Future<void> setDefaultLiveTone(String tone) async {
    _defaultLiveTone = tone;
    await _updateSetting(_liveToneKey, tone, remoteUpdates: {'assistant_persona': tone});
  }

  Future<void> setDefaultConsultantTone(String tone) async {
    _defaultConsultantTone = tone;
    await _updateSetting(_consultantToneKey, tone, remoteUpdates: {'assistant_persona': tone});
  }

  Future<void> setPushHighlights(bool val) async {
    _pushHighlights = val;
    await _updateSetting('push_highlights', val);
  }

  Future<void> setPushEvents(bool val) async {
    _pushEvents = val;
    await _updateSetting('push_events', val);
  }

  Future<void> setPushWeeklyDigest(bool val) async {
    _pushWeeklyDigest = val;
    await _updateSetting('push_weekly_digest', val);
  }

  Future<void> setPushReminders(bool val) async {
    _pushReminders = val;
    await _updateSetting('push_reminders', val);
  }

  Future<void> setPushAnnouncements(bool val) async {
    _pushAnnouncements = val;
    await _updateSetting('push_announcements', val);
  }

  Future<void> setFontSize(String size) async {
    _fontSize = size;
    await _updateSetting('font_size', size, remoteUpdates: {'font_size': size});
  }

  Future<void> setVoiceAssistantName(String name) async {
    _voiceAssistantName = name;
    await _updateSetting('voice_assistant_name', name, remoteUpdates: {'voice_assistant_name': name});
  }

  Future<void> setAssistantVoiceId(String? id) async {
    _assistantVoiceId = id;
    await _updateSetting('assistant_voice_id', id, remoteUpdates: {'assistant_voice_id': id});
  }

  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate;
    await _updateSetting('speech_rate', rate, remoteUpdates: {'speech_rate': rate});
  }

  Future<void> setPitch(double p) async {
    _pitch = p;
    await _updateSetting('pitch', p, remoteUpdates: {'pitch': p});
  }

  Future<void> setHapticFeedback(bool val) async {
    _hapticFeedback = val;
    await _updateSetting('haptic_feedback', val, remoteUpdates: {'haptic_feedback': val});
  }

  Future<void> setAutoPlayAudio(bool val) async {
    _autoPlayAudio = val;
    await _updateSetting('auto_play_audio', val, remoteUpdates: {'auto_play_audio': val});
  }

  Future<void> setTranscriptionLanguage(String lang) async {
    _transcriptionLanguage = lang;
    await _updateSetting('transcription_language', lang, remoteUpdates: {'transcription_language': lang});
  }

  Future<void> setEnableNsfwFilter(bool val) async {
    _enableNsfwFilter = val;
    await _updateSetting('enable_nsfw_filter', val, remoteUpdates: {'enable_nsfw_filter': val});
  }

  Future<void> setDataSharingOptIn(bool val) async {
    _dataSharingOptIn = val;
    await _updateSetting('data_sharing_opt_in', val, remoteUpdates: {'data_sharing_opt_in': val});
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    await _updateSetting(_localeKey, locale.languageCode);
  }
}
