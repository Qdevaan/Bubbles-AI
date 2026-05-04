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

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

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
  bool _wingmanInFlight = false;      // guard: only one wingman call at a time
  String? _lastAdviceText;            // dedup: skip Realtime if HTTP already delivered it

  final List<Map<String, dynamic>> _sessionLogs = [];
  List<Map<String, dynamic>> get sessionLogs => List.unmodifiable(_sessionLogs);

  // Paths of the last saved recording/transcript (set after endSession)
  Map<String, String>? _lastRecordingPaths;
  Map<String, String>? get lastRecordingPaths => _lastRecordingPaths;

  String _currentSuggestion = "Tap Start to begin your Wingman session...";
  String get currentSuggestion => _currentSuggestion;

  // Teleprompter history — all non-idle AI responses for this session
  final List<String> _adviceHistory = [];
  List<String> get adviceHistory => List.unmodifiable(_adviceHistory);

  void _setAdvice(String advice) {
    // Don't surface WAITING or idle system strings to the user
    final idle = [
      'WAITING', 'Listening...', 'Connecting to Deepgram...',
      'Thinking...', 'Retrying...', 'Connection Failed',
      'Tap Start to begin your Wingman session...', 'No response from server.',
    ];
    if (idle.contains(advice)) {
      // For WAITING we just leave currentSuggestion as-is (Listening...)
      notifyListeners();
      return;
    }
    _currentSuggestion = advice;
    _lastAdviceText = advice;
    if (advice.trim().isNotEmpty) {
      _adviceHistory.add(advice);
    }
    notifyListeners();
  }


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
      if (!_wingmanInFlight) {
        _askWingman(deepgram.currentTranscript, api);
      }
    } else if (_sessionId != null) {
      // Log user's own speech to server for session history
      _logUserTurn(deepgram.currentTranscript, api);
    }
  }

  /// Fire-and-forget: log user turn to server (no advice needed, just persistence).
  void _logUserTurn(String transcript, ApiService api) {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    api.sendTranscriptToWingman(
      user.id,
      transcript,
      sessionId: _sessionId,
      speakerRole: 'user',
      mode: 'live_wingman',
      persona: _currentLiveTone,
    );
  }

  Future<void> _askWingman(String transcript, ApiService api) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    _wingmanInFlight = true;
    _currentSuggestion = "Thinking...";
    _realtimeLost = false;
    _lastTranscriptForRetry = transcript;
    _lastAdviceText = null;
    notifyListeners();

    final advice = await api.sendTranscriptToWingman(
      user.id,
      transcript,
      sessionId: _sessionId,
      speakerRole: 'others',
      mode: 'live_wingman',
      persona: _currentLiveTone,
    );

    _wingmanInFlight = false;

    if (advice != null && advice.isNotEmpty && advice != 'WAITING') {
      _realtimeTimeoutTimer?.cancel();
      _setAdvice(advice);
      _realtimeLost = false;
    } else if (advice == null) {
      // HTTP returned nothing — fall back to Realtime timeout
      _realtimeTimeoutTimer?.cancel();
      // 4s HTTP + 8s here = 12s total fallback (down from 45s). Happy path is sub-500ms via cache.
      _realtimeTimeoutTimer = Timer(const Duration(seconds: 8), () {
        if (_currentSuggestion == "Thinking...") {
          _realtimeLost = true;
          notifyListeners();
        }
      });
    } else {
      // advice == 'WAITING' — nothing useful to say, reset to Listening
      _currentSuggestion = "Listening...";
      notifyListeners();
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
      mode: 'live_wingman',
      persona: _currentLiveTone,
    );
    _setAdvice(advice ?? 'No response from server.');
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
              // Dedup: HTTP already delivered this advice — skip to avoid double-entry
              if (content == _lastAdviceText) return;
              _realtimeTimeoutTimer?.cancel();
              _setAdvice(content);
              _realtimeLost = false;
            }
          },
        )
        .subscribe();
  }

  String _currentLiveTone = 'casual';
  String get currentLiveTone => _currentLiveTone;

  void changeLiveTone(String tone) {
    if (_currentLiveTone == tone) return;
    _currentLiveTone = tone;
    notifyListeners();
  }

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
    _isConnecting = true;
    _sessionLogs.clear();
    _adviceHistory.clear();
    _currentSuggestion = "Connecting to Deepgram...";
    _wingmanInFlight = false;
    _lastAdviceText = null;

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

    _isConnecting = false;
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
