import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

class LiveKitService extends ChangeNotifier {
  ApiService _apiService;
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  String _currentTranscript = "";
  String get currentTranscript => _currentTranscript;

  String _currentAdvice = "";
  String get currentAdvice => _currentAdvice;

  String _currentSpeaker = "user";
  String get currentSpeaker => _currentSpeaker;

  LiveKitService(this._apiService);

  /// Update the API service reference without recreating the whole service.
  /// This preserves the LiveKit connection state across Provider updates.
  void updateApiService(ApiService apiService) {
    _apiService = apiService;
  }

  String? _lastUserId;

  Future<void> connect(String userId, {String roomName = ""}) async {
    if (_isConnected) return;
    _lastUserId = userId;

    // 1. Get Token from Server
    try {
      final tokenData = await _apiService.getToken(userId, roomName: roomName);
      if (tokenData == null) {
        debugPrint("Failed to get LiveKit token — null response");
        return;
      }

      final String url = tokenData['url'];
      final String token = tokenData['token'];

      // 2. Connect to Room
      _room = Room();
      _listener = _room!.createListener();

      await _room!.connect(url, token);
      _isConnected = true;
      notifyListeners();

      // 3. Enable Microphone
      await _room!.localParticipant?.setMicrophoneEnabled(true);

      // 4. Listen for Data (Transcripts)
      _listener!.on<DataReceivedEvent>((event) {
        try {
          final String dataStr = utf8.decode(event.data);
          final Map<String, dynamic> data = jsonDecode(dataStr);

          if (data['type'] == 'transcript') {
            final String text = data['text'];
            final bool isFinal = data['is_final'] ?? false;
            final String speaker = data['speaker'] ?? "user";

            debugPrint(
              "TRANSCRIPT: $text (Final: $isFinal, Speaker: $speaker)",
            );

            _currentTranscript = text;
            _currentSpeaker = speaker;
            notifyListeners();
          } else if (data['type'] == 'assistant_response') {
            final String text = data['text'];
            debugPrint("ADVICE: $text");
            _currentAdvice = text;
            notifyListeners();
          }
        } catch (e) {
          debugPrint("Error parsing data: $e");
        }
      });

      // 5. Listen for room disconnect and attempt reconnection
      _listener!.on<RoomDisconnectedEvent>((event) {
        debugPrint("LiveKit room disconnected, attempting reconnect...");
        _isConnected = false;
        notifyListeners();
        if (_lastUserId != null) {
          Future.delayed(const Duration(seconds: 2), () {
            connect(_lastUserId!);
          });
        }
      });
    } catch (e) {
      debugPrint("LiveKit Connection Error: $e");
      _isConnected = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (_room != null) {
      await _room!.disconnect();
      _room = null;
    }
    _isConnected = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _listener?.dispose();
    _room?.dispose();
    super.dispose();
  }
}
