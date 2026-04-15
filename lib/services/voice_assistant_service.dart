import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';
import 'connection_service.dart';
import 'wake_word_service.dart';

// ─── Enums ───────────────────────────────────────────────

/// The current state of the voice assistant pipeline.
enum VoiceAssistantState {
  idle, // Not active — waiting for wake word or tap
  listening, // Wake word detected — actively capturing command
  processing, // Command captured — sending to server
  speaking, // TTS reading out the response
}

/// Voice modes the user can choose from.
/// Each maps to a specific Deepgram Aura voice model.
enum VoiceMode {
  male, // aura-arcas-en   — masculine, confident
  female, // aura-asteria-en — feminine, clear, energetic
  neutral, // aura-orpheus-en — neutral, professional
}

// ─── Service ────────────────────────────────────────────

class VoiceAssistantService extends ChangeNotifier {
  // ── Dependencies ──
  final ConnectionService _connectionService;
  final WakeWordService _wakeWordService;

  // ── Speech-to-Text (used ONLY for command capture, NOT wake word) ──
  final SpeechToText _stt = SpeechToText();
  bool _sttInitialized = false;

  // ── Deepgram Aura TTS (proxied through backend) ──
  final AudioPlayer _audioPlayer = AudioPlayer();

  // ── State ──
  VoiceAssistantState _state = VoiceAssistantState.idle;
  VoiceAssistantState get state => _state;

  String _lastResponse = '';
  String get lastResponse => _lastResponse;

  String _partialText = '';
  String get partialText => _partialText;

  bool _isWakeWordEnabled = true;
  bool get isWakeWordEnabled => _isWakeWordEnabled;

  bool _isOverlayVisible = false;
  bool get isOverlayVisible => _isOverlayVisible;

  /// Whether the service is active (user is authenticated and on a main screen).
  bool _isActive = false;
  bool get isActive => _isActive;

  VoiceMode _voiceMode = VoiceMode.neutral;
  VoiceMode get voiceMode => _voiceMode;

  // ── Prefs keys ──
  static const String _voiceModeKey = 'voice_mode';
  static const String _wakeWordKey = 'wake_word_enabled';

  // ── Constructor ──
  VoiceAssistantService(this._connectionService, this._wakeWordService) {
    // Wire up the wake word callback
    _wakeWordService.onWakeWordDetected = _onWakeWordDetected;
    _init();
  }

  // ─── Initialisation ───────────────────────────────────

  Future<void> _init() async {
    await _loadPreferences();
    await _initSTT();
    _initDeepgramTTS();
    await _wakeWordService.init();
    // Don't auto-start wake word listening here.
    // Wait for activate() to be called (e.g. from HomeScreen).
  }

  /// Call this when user is authenticated and on a main screen.
  /// Wake word listening always starts here (unless explicitly disabled in settings).
  void activate() {
    if (_isActive) return;
    _isActive = true;
    debugPrint('🎙️ Voice assistant activated');
    // Always start wake word on activation — user can disable in settings if needed
    if (_isWakeWordEnabled) {
      _wakeWordService.init().then((_) {
        if (_isActive && _isWakeWordEnabled) {
          _wakeWordService.startListening();
        }
      });
    }
  }

  /// Call this when user logs out or navigates to auth screens.
  void deactivate() {
    if (!_isActive) return;
    _isActive = false;
    debugPrint('🎙️ Voice assistant deactivated');
    _wakeWordService.stopListening();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_voiceModeKey) ?? VoiceMode.neutral.index;
    _voiceMode =
        VoiceMode.values[modeIndex.clamp(0, VoiceMode.values.length - 1)];
    _isWakeWordEnabled = prefs.getBool(_wakeWordKey) ?? true;
    notifyListeners();
    _loadFromSupabase();
  }

  Future<void> _loadFromSupabase() async {
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) return;
      final row = await Supabase.instance.client
          .from('user_settings')
          .select('voice_mode')
          .eq('user_id', user.id)
          .maybeSingle();
      if (row != null && row['voice_mode'] != null) {
        final modeStr = row['voice_mode'] as String;
        VoiceMode? matchedMode;
        for (var vm in VoiceMode.values) {
          if (vm.name == modeStr) {
            matchedMode = vm;
            break;
          }
        }
        if (matchedMode != null && matchedMode != _voiceMode) {
          _voiceMode = matchedMode;
          notifyListeners();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(_voiceModeKey, _voiceMode.index);
        }
      }
    } catch (e) {
      debugPrint('VoiceAssistantService._loadFromSupabase: $e');
    }
  }

  Future<void> _upsertVoiceMode(VoiceMode mode) async {
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) return;
      await Supabase.instance.client.from('user_settings').upsert({
        'user_id': user.id,
        'voice_mode': mode.name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('VoiceAssistantService._upsertVoiceMode: $e');
    }
  }

  Future<void> _initSTT() async {
    try {
      _sttInitialized = await _stt.initialize(
        onError: (error) => debugPrint('🎙️ STT error: ${error.errorMsg}'),
      );
      debugPrint('🎙️ STT initialized: $_sttInitialized');
    } catch (e) {
      debugPrint('🎙️ STT init failed: $e');
    }
  }

  void _initDeepgramTTS() {
    debugPrint('🔊 Deepgram Aura TTS initialized (backend proxy)');

    // When audio finishes playing, return to idle and restart wake word
    _audioPlayer.onPlayerComplete.listen((_) {
      _setState(VoiceAssistantState.idle);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_isActive && _isWakeWordEnabled) {
          _wakeWordService.startListening();
        }
      });
    });
  }

  // ─── Voice Mode ───────────────────────────────────────

  /// Returns the Deepgram Aura model name for the current voice mode.
  String get _deepgramModel {
    switch (_voiceMode) {
      case VoiceMode.male:
        return 'aura-arcas-en';
      case VoiceMode.female:
        return 'aura-asteria-en';
      case VoiceMode.neutral:
        return 'aura-orpheus-en';
    }
  }

  Future<void> setVoiceMode(VoiceMode mode) async {
    _voiceMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_voiceModeKey, mode.index);
    _upsertVoiceMode(mode);
    // No need to reconfigure anything — _deepgramModel getter handles it
  }

  // ─── Wake Word Toggle ────────────────────────────────

  Future<void> setWakeWordEnabled(bool enabled) async {
    _isWakeWordEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wakeWordKey, enabled);

    if (enabled && _isActive) {
      // Ensure Porcupine is initialised before trying to start
      await _wakeWordService.init();
      await _wakeWordService.startListening();
    } else {
      await _wakeWordService.stopListening();
    }
  }

  // ─── Wake Word Detected (Porcupine Callback) ─────────

  void _onWakeWordDetected() async {
    debugPrint('🎙️ ✅ Wake word "Hey Bubbles" detected via Porcupine!');

    // Stop Porcupine while we capture the user's command
    // (avoids microphone conflict with speech_to_text)
    await _wakeWordService.stopListening();

    // Add a tiny delay to ensure audio hardware is fully released
    await Future.delayed(const Duration(milliseconds: 300));

    // Show overlay and start active command listening
    _showOverlay();
    _startCommandListening();
  }

  // ─── Active Command Listening (STT) ──────────────────

  void _startCommandListening() {
    if (!_sttInitialized) return;

    _setState(VoiceAssistantState.listening);
    _partialText = '';
    notifyListeners();

    _stt.listen(
      onResult: _onCommandResult,
      listenMode: ListenMode.confirmation,
      pauseFor: const Duration(seconds: 3),
      cancelOnError: false,
      partialResults: true,
    );
  }

  void _onCommandResult(SpeechRecognitionResult result) {
    if (_state == VoiceAssistantState.processing)
      return; // Prevent multiple calls

    _partialText = result.recognizedWords;
    notifyListeners();

    // Wait for STT to finalize — all intent parsing is handled by the
    // server's /voice_command endpoint via LLM, not keyword matching.
    if (result.finalResult) {
      final command = result.recognizedWords.trim();
      debugPrint('🎙️ Command captured: "$command"');
      if (command.isNotEmpty) {
        _processCommand(command);
      } else {
        // No command heard — go back to idle
        _setState(VoiceAssistantState.idle);
        _hideOverlayAfterDelay();
      }
    }
  }

  // ─── Command Processing ──────────────────────────────

  Future<void> _processCommand(String command) async {
    _setState(VoiceAssistantState.processing);
    _partialText = command;
    notifyListeners();

    final lowerCommand = command.toLowerCase();

    // Check server connection
    if (!_connectionService.isConnected ||
        _connectionService.serverUrl.isEmpty) {
      await _speak(
        "I can't reach the server right now. Please check your connection in settings.",
      );
      return;
    }

    try {
      final userId = _getUserId();

      // Start E2E Latency Stopwatch
      final stopwatch = Stopwatch()..start();

      final response = await _sendVoiceCommand(userId, command);

      stopwatch.stop();
      final double latencySeconds = stopwatch.elapsedMilliseconds / 1000.0;
      debugPrint(
        '[LATENCY] Wingman round trip: ${latencySeconds.toStringAsFixed(2)}s',
      );

      if (response != null) {
        _lastResponse =
            response['response'] ?? "I'm not sure how to help with that.";
        final action = response['action'] as String? ?? 'none';
        final target = response['target'] as String?;

        // Speak the response
        await _speak(_lastResponse);

        // Execute navigation action after speaking starts
        if (action == 'navigate' && target != null) {
          _pendingNavigationRoute = target;
          _pendingNavigationArgs = null;
          hideOverlay();
        }
      } else {
        await _speak(
          "Sorry, I had trouble processing that. Can you try again?",
        );
      }
    } catch (e) {
      debugPrint('❌ Voice command error: $e');
      await _speak("Something went wrong. Please try again.");
    }
  }

  String? _pendingNavigationRoute;
  Object? _pendingNavigationArgs;

  /// Call this from the overlay widget to get & consume pending navigation.
  Map<String, dynamic>? consumePendingNavigation() {
    if (_pendingNavigationRoute == null) return null;
    final nav = {
      'route': _pendingNavigationRoute,
      'args': _pendingNavigationArgs,
    };
    _pendingNavigationRoute = null;
    _pendingNavigationArgs = null;
    return nav;
  }

  String _getUserId() {
    try {
      return _userId ?? 'anonymous';
    } catch (e) {
      return 'anonymous';
    }
  }

  String? _userId;
  void setUserId(String id) {
    _userId = id;
  }

  Future<Map<String, dynamic>?> _sendVoiceCommand(
    String userId,
    String command,
  ) async {
    try {
      final uri = Uri.parse('${_connectionService.serverUrl}/v1/voice_command');
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
            body: jsonEncode({'user_id': userId, 'command': command}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        debugPrint(
          '❌ Voice command server error: ${response.statusCode} ${response.body}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('❌ Voice command network error: $e');
      return null;
    }
  }

  // ─── Deepgram Aura TTS ──────────────────────────────

  /// Speaks text using the backend TTS proxy (which forwards to Deepgram Aura).
  /// Sends text to the backend, receives MP3 audio bytes, and plays them.
  Future<void> _speak(String text) async {
    _lastResponse = text;
    _setState(VoiceAssistantState.speaking);
    notifyListeners();

    final serverUrl = _connectionService.serverUrl;
    final jwt = Supabase.instance.client.auth.currentSession?.accessToken ?? '';

    if (serverUrl.isEmpty || jwt.isEmpty) {
      debugPrint('⚠️ Deepgram TTS: serverUrl or jwt is empty, skipping audio playback');
      Future.delayed(const Duration(seconds: 2), () {
        _setState(VoiceAssistantState.idle);
        if (_isActive && _isWakeWordEnabled) {
          _wakeWordService.startListening();
        }
      });
      return;
    }

    try {
      debugPrint(
        '🔊 Deepgram TTS: Requesting audio via backend proxy (model=$_deepgramModel)',
      );

      final response = await http
          .post(
            Uri.parse('$serverUrl/v1/tts'),
            headers: {
              'Authorization': 'Bearer $jwt',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'text': text, 'model': _deepgramModel}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        // Save audio bytes to a temp file and play
        final tempDir = await getTemporaryDirectory();
        final audioFile = File('${tempDir.path}/bubbles_tts_response.mp3');
        await audioFile.writeAsBytes(response.bodyBytes);

        await _audioPlayer.play(DeviceFileSource(audioFile.path));
        debugPrint(
          '🔊 Deepgram TTS: Playing audio (${response.bodyBytes.length} bytes)',
        );
      } else {
        debugPrint(
          '❌ Deepgram TTS error: ${response.statusCode} ${response.body}',
        );
        _setState(VoiceAssistantState.idle);
        if (_isActive && _isWakeWordEnabled) {
          _wakeWordService.startListening();
        }
      }
    } catch (e) {
      debugPrint('❌ Deepgram TTS network error: $e');
      _setState(VoiceAssistantState.idle);
      if (_isActive && _isWakeWordEnabled) {
        _wakeWordService.startListening();
      }
    }
  }

  // ─── Overlay Visibility ──────────────────────────────

  void _showOverlay() {
    _isOverlayVisible = true;
    notifyListeners();
  }

  void hideOverlay() {
    _isOverlayVisible = false;
    _setState(VoiceAssistantState.idle);
    _audioPlayer.stop();
    if (_stt.isListening) {
      _stt.stop();
    }
    notifyListeners();
    // Restart Porcupine wake word listening
    if (_isActive && _isWakeWordEnabled) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _wakeWordService.startListening();
      });
    }
  }

  void _hideOverlayAfterDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (_state == VoiceAssistantState.idle) {
        hideOverlay();
      }
    });
  }

  // ─── Helpers ─────────────────────────────────────────

  void _setState(VoiceAssistantState newState) {
    _state = newState;
    notifyListeners();
  }

  @override
  void dispose() {
    _stt.stop();
    _audioPlayer.dispose();
    super.dispose();
  }
}
