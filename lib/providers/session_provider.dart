import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/deepgram_service.dart';
import '../services/analytics_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dedicated state manager for the NewSession (Live Wingman) screen.
/// Extracts Deepgram connection, Realtime subscription, session state,
/// and transcript management out of the widget into a proper provider.
class SessionProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ── Session state ──
  bool _isSessionActive = false;
  bool get isSessionActive => _isSessionActive;

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  bool _swapSpeakers = false;
  bool get swapSpeakers => _swapSpeakers;

  String? _sessionId;
  String? get sessionId => _sessionId;

  RealtimeChannel? _realtimeChannel;

  // ── Realtime drop detection ──
  Timer? _realtimeTimeoutTimer;
  bool _realtimeLost = false;
  bool get realtimeLost => _realtimeLost;

  String? _lastTranscriptForRetry;

  final List<Map<String, dynamic>> _sessionLogs = [];
  List<Map<String, dynamic>> get sessionLogs => List.unmodifiable(_sessionLogs);

  // Paths of the last saved recording/transcript (set after endSession)
  Map<String, String>? _lastRecordingPaths;
  Map<String, String>? get lastRecordingPaths => _lastRecordingPaths;

  String _currentSuggestion = "Tap Start to begin your Wingman session...";
  String get currentSuggestion => _currentSuggestion;

  void toggleSwapSpeakers() {
    _swapSpeakers = !_swapSpeakers;
    notifyListeners();
    AnalyticsService.instance.logAction(
      action: 'speakers_swapped',
      entityType: 'session',
      entityId: _sessionId,
      details: {'swap_speakers': _swapSpeakers},
    );
  }

  /// Process new transcript from Deepgram.
  void onTranscriptReceived(DeepgramService deepgram, ApiService api) {
    if (deepgram.currentTranscript.isEmpty) return;
    if (_sessionLogs.isNotEmpty &&
        _sessionLogs.last['text'] == deepgram.currentTranscript)
      return;

    String serverSpeaker = deepgram.currentSpeaker == "user" ? "User" : "Other";
    String finalSpeaker = serverSpeaker;
    if (_swapSpeakers)
      finalSpeaker = serverSpeaker == "User" ? "Other" : "User";

    _sessionLogs.add({
      "speaker": finalSpeaker,
      "text": deepgram.currentTranscript,
    });
    notifyListeners();

    if (finalSpeaker == "Other") {
      _askWingman(deepgram.currentTranscript, api);
    }
  }

  Future<void> _askWingman(String transcript, ApiService api) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    _currentSuggestion = "Thinking...";
    _realtimeLost = false;
    _lastTranscriptForRetry = transcript;
    notifyListeners();

    // Always await the HTTP response directly — this works regardless of
    // whether Supabase Realtime is configured on session_logs.
    // Realtime still fires as a secondary update if it is configured.
    final advice = await api.sendTranscriptToWingman(
      user.id,
      transcript,
      sessionId: _sessionId,
      speakerRole: 'others',
      mode: _currentLiveTone,
    );

    if (advice != null && advice.isNotEmpty) {
      _realtimeTimeoutTimer?.cancel();
      _currentSuggestion = advice;
      _realtimeLost = false;
      notifyListeners();
    } else {
      // HTTP returned nothing — fall back to Realtime timeout
      _realtimeTimeoutTimer?.cancel();
      _realtimeTimeoutTimer = Timer(const Duration(seconds: 30), () {
        if (_currentSuggestion == "Thinking...") {
          _realtimeLost = true;
          notifyListeners();
        }
      });
    }
  }

  Future<void> retryWingman(ApiService api) async {
    if (_lastTranscriptForRetry == null) return;
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    _realtimeLost = false;
    _currentSuggestion = "Retrying...";
    notifyListeners();

    final advice = await api.sendTranscriptToWingman(
      user.id,
      _lastTranscriptForRetry!,
    );
    _currentSuggestion = advice ?? "No response from server.";
    notifyListeners();
  }

  /// Subscribe to Realtime suggestions from the server.
  void subscribeToLiveSuggestions(String sessionId) {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = _supabase
        .channel('live_session_$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'session_logs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (PostgresChangePayload payload) {
            final record = payload.newRecord;
            final role = record['role'] as String?;
            final content = record['content'] as String?;
            if (role == 'llm' && content != null && content.isNotEmpty) {
              _realtimeTimeoutTimer?.cancel();
              _currentSuggestion = content;
              _realtimeLost = false;
              notifyListeners();
            }
          },
        )
        .subscribe();
  }

  String _currentLiveTone = 'casual';

  Future<void> startSession(
    ApiService api,
    DeepgramService deepgram, {
    String tone = 'casual',
    String? targetEntityId,
    bool isEphemeral = false,
    bool isMultiplayer = false,
    required String serverUrl,
    required String jwt,
  }) async {
    _currentLiveTone = tone;
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    _isSessionActive = true;
    _sessionLogs.clear();
    _currentSuggestion = "Connecting to Deepgram...";
    _sessionId = null;
    notifyListeners();

    String sessionMode = targetEntityId != null ? 'roleplay' : 'live_wingman';

    final sid = await api.createLiveSession(
      user.id, 
      mode: sessionMode, 
      targetEntityId: targetEntityId,
      isEphemeral: isEphemeral,
      isMultiplayer: isMultiplayer,
      persona: tone,
    );
    if (sid != null) {
      _sessionId = sid;
      subscribeToLiveSuggestions(sid);
      debugPrint('Live session created: $sid');
    }

    await deepgram.connect(serverUrl: serverUrl, jwt: jwt);

    if (deepgram.isConnected) {
      _currentSuggestion = "Listening...";
    } else {
      _isSessionActive = false;
      _currentSuggestion = "Connection Failed";
    }
    notifyListeners();

    AnalyticsService.instance.logAction(
      action: 'session_started',
      entityType: 'session',
      entityId: _sessionId,
      details: {
        'mode': sessionMode,
        'tone': tone,
        'is_ephemeral': isEphemeral,
        'is_multiplayer': isMultiplayer,
        if (targetEntityId != null) 'target_entity_id': targetEntityId,
      },
    );
  }

  /// End the session, save data, and persist audio recording to device.
  Future<bool> endSession(ApiService api, DeepgramService deepgram) async {
    _isSessionActive = false;
    _lastRecordingPaths = null;
    notifyListeners();

    // Save audio + transcript before disconnecting (buffer lives in deepgram)
    if (_sessionId != null && deepgram.fullTranscript.isNotEmpty) {
      _lastRecordingPaths = await deepgram.saveSessionRecording(_sessionId!);
    }

    await deepgram.disconnect();

    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    _realtimeTimeoutTimer?.cancel();
    _realtimeTimeoutTimer = null;
    _realtimeLost = false;

    final user = AuthService.instance.currentUser;
    if (user == null) return true;

    _isSaving = true;
    notifyListeners();

    try {
      bool success = false;
      if (_sessionId != null) {
        await api.endLiveSession(_sessionId!, user.id);
        success = true;
        // Mark first wingman as done
        await AuthService.instance.updateOnboardingProgress({'first_wingman': true});
      } else if (_sessionLogs.isNotEmpty) {
        success = await api.saveSession(user.id, _sessionLogs);
      } else {
        success = true;
      }
      return success;
    } catch (e) {
      debugPrint("Save failed: $e");
      return false;
    } finally {
      AnalyticsService.instance.logAction(
        action: 'session_ended',
        entityType: 'session',
        entityId: _sessionId,
        details: {'log_count': _sessionLogs.length},
      );
      _isSaving = false;
      _sessionId = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _realtimeTimeoutTimer?.cancel();
    super.dispose();
  }
}
