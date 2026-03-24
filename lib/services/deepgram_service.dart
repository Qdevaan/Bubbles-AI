import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

class DeepgramService extends ChangeNotifier {
  // CONFIG — loaded from environment variables
  static String get _apiKey => dotenv.env['DEEPGRAM_API_KEY'] ?? '';
  static const String _wsUrl =
      "wss://api.deepgram.com/v1/listen?smart_format=true&diarize=true&model=nova-2";

  // STATE
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  String _currentTranscript = "";
  String get currentTranscript => _currentTranscript;

  String _currentSpeaker = "user";
  String get currentSpeaker => _currentSpeaker;

  // INTERNAL
  final AudioRecorder _recorder = AudioRecorder();
  WebSocketChannel? _channel;
  StreamSubscription? _audioStreamSubscription;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  bool _intentionalDisconnect = false;

  Future<void> connect() async {
    if (_isConnected) return;
    _intentionalDisconnect = false;
    _reconnectAttempts = 0;

    if (_apiKey.isEmpty) {
      debugPrint("❌ DeepgramService: No API key found in .env");
      return;
    }

    try {
      // 1. Check Permissions
      if (!await _recorder.hasPermission()) {
        debugPrint("❌ DeepgramService: No microphone permission");
        return;
      }

      // 2. Connect WebSocket with Auth Header
      _channel = IOWebSocketChannel.connect(
        Uri.parse(_wsUrl),
        headers: {'Authorization': 'Token $_apiKey'},
      );

      await _channel!.ready;
      debugPrint("✅ DeepgramService: WebSocket Connected");
      _isConnected = true;
      notifyListeners();

      // 3. Start Audio Stream
      // Using AAC LC which is generally supported for streaming
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      // 4. Send Audio to WebSocket
      _audioStreamSubscription = stream.listen((data) {
        if (_channel != null) {
          _channel!.sink.add(data);
        }
      });

      // 5. Listen for Transcripts
      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onError: (error) {
          debugPrint("❌ DeepgramService: WebSocket Error: $error");
          _attemptReconnect();
        },
        onDone: () {
          debugPrint("⚠️ DeepgramService: WebSocket Closed");
          _attemptReconnect();
        },
      );
    } catch (e) {
      debugPrint("❌ DeepgramService: Connection Failed: $e");
      disconnect();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

      // Check if it's a transcript
      if (data['type'] == 'Results') {
        final channel = data['channel'];
        final alternatives = channel['alternatives'] as List;
        if (alternatives.isNotEmpty) {
          final alt = alternatives[0];
          final transcript = alt['transcript'] as String;

          if (transcript.trim().isNotEmpty && data['is_final'] == true) {
            // Extract Speaker
            int speakerId = 0;
            if (alt['words'] != null && (alt['words'] as List).isNotEmpty) {
              speakerId = alt['words'][0]['speaker'];
            }

            _currentTranscript = transcript;
            _currentSpeaker = speakerId == 0
                ? "user"
                : "other"; // Simple mapping

            debugPrint("🗣️ Deepgram: [$_currentSpeaker] $transcript");
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint("Error parsing Deepgram message: $e");
    }
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _isConnected = false;
    notifyListeners();

    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;

    await _recorder.stop();

    await _channel?.sink.close();
    _channel = null;
  }

  void _attemptReconnect() {
    if (_intentionalDisconnect) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint("❌ DeepgramService: Max reconnect attempts reached");
      disconnect();
      return;
    }
    _isConnected = false;
    _channel = null;
    notifyListeners();
    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts * 2);
    debugPrint("🔄 DeepgramService: Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)");
    Future.delayed(delay, () {
      if (!_intentionalDisconnect) connect();
    });
  }
}
