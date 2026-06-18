// Purpose: Wraps the DaVoice SDK (flutter_wake_word) to listen for the 'Hey Bubbles' wake word and fire a callback when detected.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_wake_word/flutter_wake_word.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service that wraps DaVoice for on-device wake word detection.
///
/// Uses the custom "Hey Bubbles" .onnx model for efficient, always-on,
/// offline wake word detection.
class WakeWordService extends ChangeNotifier with WidgetsBindingObserver {
  KeyWordFlutterPC? _wakewordDetector;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  bool _isListening = false;
  bool _isInitialized = false;
  bool _isInitializing = false; // guard against concurrent init calls

  bool _wasListeningBeforePause = false;

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;

  /// Callback fired when the wake word is detected.
  VoidCallback? onWakeWordDetected;

  /// Optional callback for user-facing error notifications.
  void Function(String message)? onError;

  // Initialisation

  WakeWordService() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (_isListening) {
        _wasListeningBeforePause = true;
        stopListening();
        debugPrint('🎙️ DaVoice: Paused listening due to app backgrounding');
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_wasListeningBeforePause && !_isListening && _isInitialized) {
        startListening();
        _wasListeningBeforePause = false;
        debugPrint('🎙️ DaVoice: Resumed listening after app foregrounding');
      }
    }
  }

  /// Creates the DaVoice wake word instance and sets the license key.
  /// Must be called once before [startListening].
  Future<void> init() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;

    final licenseKey = dotenv.env['DAVOICE_LICENSE_KEY'] ?? '';
    if (licenseKey.isEmpty) {
      debugPrint('⚠️ DaVoice: No valid DAVOICE_LICENSE_KEY found in .env');
      _isInitializing = false;
      return;
    }

    try {
      // Ensure microphone permission is granted
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final requested = await Permission.microphone.request();
        if (!requested.isGranted) {
          debugPrint('❌ DaVoice: Microphone permission was not granted.');
          onError?.call('Microphone permission required for wake word detection.');
          _isInitializing = false;
          return;
        }
      }

      final String instanceId = 'bubbles_wakeword';
      // Path/filename of the ONNX model bundle on device
      final String modelName = 'hey_bubbles.onnx';

      _wakewordDetector = createKeyWordFlutterPCInstance(instanceId);

      // Set license key
      final licenseSuccess = await _wakewordDetector!.setKeywordDetectionLicense(licenseKey);
      if (!licenseSuccess) {
        debugPrint('❌ DaVoice: License activation failed');
        onError?.call('DaVoice wake word license activation failed.');
        _isInitializing = false;
        return;
      }

      // Create wake word instance on native side
      // threshold: 0.999 (default for DaVoice)
      // bufferCount: 3
      // msBetweenCallbacks: 1000
      await _wakewordDetector!.createInstanceMulti(
        instanceId,
        [modelName],
        const [0.999],
        const [3],
        const [1000],
      );

      // Subscribe to detection events
      _subscription = _wakewordDetector!.onKeywordDetectionEvent().listen((event) {
        _onWakeWordEvent(event);
      });

      _isInitialized = true;
      debugPrint('🎙️ DaVoice: Initialized successfully');
    } catch (e) {
      debugPrint('❌ DaVoice init error: $e');
      onError?.call('Wake word init failed: $e');
    } finally {
      _isInitializing = false;
    }
  }

  // Detection Callback

  void _onWakeWordEvent(Map<String, dynamic> event) {
    final phrase = event['phrase']?.toString() ?? event['model']?.toString() ?? 'Hey Bubbles';
    debugPrint('🎙️ DaVoice: Wake word detected! ($phrase)');
    // Notify the VoiceAssistantService
    onWakeWordDetected?.call();
  }

  // Listening Control

  /// Start listening for the wake word.
  Future<void> startListening() async {
    if (!_isInitialized || _isListening) return;

    try {
      final success = await _wakewordDetector!.startKeywordDetection(
        'bubbles_wakeword',
        0.999,
      );
      if (success) {
        _isListening = true;
        debugPrint('🎙️ DaVoice: Listening for "Hey Bubbles"...');
        notifyListeners();
      } else {
        debugPrint('❌ DaVoice: startKeywordDetection returned false');
      }
    } catch (e) {
      debugPrint('❌ DaVoice start error: $e');
    }
  }

  /// Stop listening for the wake word.
  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      await _wakewordDetector!.stopKeywordDetection('bubbles_wakeword');
      _isListening = false;
      debugPrint('🎙️ DaVoice: Stopped listening');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ DaVoice stop error: $e');
    }
  }

  // Cleanup

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _wakewordDetector?.destroyInstance();
    _wakewordDetector = null;
    _isInitialized = false;
    _isListening = false;
    super.dispose();
  }
}
