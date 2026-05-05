import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

class DeepgramService extends ChangeNotifier {
  // STATE
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  String _currentTranscript = "";
  String get currentTranscript => _currentTranscript;

  String _currentSpeaker = "user";
  String get currentSpeaker => _currentSpeaker;

  double _currentConfidence = 1.0;
  double get currentConfidence => _currentConfidence;

  // Recording state
  final BytesBuilder _audioBuffer = BytesBuilder(copy: true);
  final List<Map<String, dynamic>> _fullTranscript = [];
  double _audioElapsed = 0.0; // seconds of audio recorded so far
  String? _lastSavedAudioPath;
  String? _lastSavedTranscriptPath;
  String? _lastSavedTimingPath;
  String? get lastSavedAudioPath => _lastSavedAudioPath;
  String? get lastSavedTranscriptPath => _lastSavedTranscriptPath;
  String? get lastSavedTimingPath => _lastSavedTimingPath;
  List<Map<String, dynamic>> get fullTranscript =>
      List.unmodifiable(_fullTranscript);

  // Speaker identity (enrollment-based)
  final Map<int, String> _speakerIdentityCache = {};
  final Set<int> _pendingIdentification = {};
  String? _serverUrl;
  String? _jwt;
  String? _userId;

  // INTERNAL
  final AudioRecorder _recorder = AudioRecorder();
  WebSocketChannel? _channel;
  StreamSubscription? _audioStreamSubscription;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  bool _intentionalDisconnect = false;

  Future<void> connect({
    required String serverUrl,
    required String jwt,
    String? userId,
  }) async {
    if (_isConnected) return;
    _intentionalDisconnect = false;
    _reconnectAttempts = 0;
    _serverUrl = serverUrl;
    _jwt = jwt;
    _userId = userId;
    _speakerIdentityCache.clear();
    _pendingIdentification.clear();

    if (serverUrl.isEmpty || jwt.isEmpty) {
      debugPrint("❌ DeepgramService: serverUrl or jwt is empty");
      return;
    }

    // Convert http(s) base URL to ws(s)
    final wsBase = serverUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final wsUrl = '$wsBase/v1/stt/stream'
        '?token=$jwt'
        '&smart_format=true&diarize=true&model=nova-2'
        '&encoding=linear16&sample_rate=16000&channels=1';

    try {
      if (!await _recorder.hasPermission()) {
        debugPrint("❌ DeepgramService: No microphone permission");
        return;
      }

      _channel = IOWebSocketChannel.connect(Uri.parse(wsUrl));
      await _channel!.ready;
      debugPrint("✅ DeepgramService: WebSocket Connected via backend proxy");
      _isConnected = true;
      notifyListeners();

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _audioBuffer.clear();
      _fullTranscript.clear();
      _audioElapsed = 0.0;
      _isMuted = false;

      // Cancel any leftover subscription before starting a new one
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      _audioStreamSubscription = stream.listen((data) {
        if (!_isMuted) {
          _channel?.sink.add(data);
          _audioBuffer.add(data);
        }
      });

      _channel!.stream.listen(
        (message) => _handleMessage(message),
        onError: (error) {
          debugPrint("❌ DeepgramService: WebSocket Error: $error");
          _attemptReconnect(serverUrl: serverUrl, jwt: jwt);
        },
        onDone: () {
          debugPrint("⚠️ DeepgramService: WebSocket Closed");
          _attemptReconnect(serverUrl: serverUrl, jwt: jwt);
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
            int speakerId = 0;
            double startSec = (data['start'] as num?)?.toDouble() ?? _audioElapsed;
            final words = alt['words'] as List?;
            if (words != null && words.isNotEmpty) {
              final firstWord = words[0] as Map;
              speakerId = firstWord['speaker'] as int? ?? 0;
              startSec = (firstWord['start'] as num?)?.toDouble() ?? startSec;
              debugPrint("🔍 Deepgram words sample: speaker=${firstWord['speaker']}, word=${firstWord['word']}");
              double totalConf = 0;
              for (final w in words) {
                totalConf += ((w as Map)['confidence'] as num?)?.toDouble() ?? 1.0;
              }
              _currentConfidence = totalConf / words.length;
            } else {
              debugPrint("⚠️ Deepgram: words array is null/empty — diarization data missing, defaulting to speakerId=0");
              _currentConfidence = 0.5;
            }
            final turnEnd = startSec + ((data['duration'] as num?)?.toDouble() ?? 0);
            _audioElapsed = turnEnd;

            _currentTranscript = transcript;

            // Use cached identity if available, else resolve async with fallback
            if (_speakerIdentityCache.containsKey(speakerId)) {
              _currentSpeaker = _speakerIdentityCache[speakerId]!;
            } else {
              // Optimistic fallback while identification runs
              _currentSpeaker = speakerId == 0 ? "user" : "other";
              if (!_pendingIdentification.contains(speakerId)) {
                _pendingIdentification.add(speakerId);
                _identifySpeaker(speakerId, startSec, turnEnd);
              }
            }

            _fullTranscript.add({
              'speaker': _currentSpeaker,
              'text': transcript,
              'start': startSec,
            });

            debugPrint("🗣️ Deepgram: [speakerId=$speakerId → $_currentSpeaker] $transcript");
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint("Error parsing Deepgram message: $e");
    }
  }

  /// Extract audio for [startSec..endSec], POST to /v1/identify_speaker,
  /// update cache, and back-patch any transcript entries for this speakerId.
  Future<void> _identifySpeaker(int speakerId, double startSec, double endSec) async {
    final url = _serverUrl;
    final jwt = _jwt;
    final userId = _userId;
    if (url == null || jwt == null || userId == null || url.isEmpty) return;

    try {
      // PCM 16-bit mono 16 kHz → 32 000 bytes/second
      const int bytesPerSec = 32000;
      final allBytes = _audioBuffer.toBytes();
      final startByte = (startSec * bytesPerSec).toInt().clamp(0, allBytes.length);
      final endByte = (endSec * bytesPerSec).toInt().clamp(startByte, allBytes.length);

      if (endByte - startByte < bytesPerSec ~/ 2) {
        // Less than 0.5 s — not enough signal; keep fallback
        _pendingIdentification.remove(speakerId);
        return;
      }

      final pcmSlice = allBytes.sublist(startByte, endByte);
      final wavBytes = _buildWavBytes(pcmSlice);

      final dir = await getTemporaryDirectory();
      final tmpFile = File('${dir.path}/speaker_id_${speakerId}_${DateTime.now().millisecondsSinceEpoch}.wav');
      await tmpFile.writeAsBytes(wavBytes);

      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$url/v1/identify_speaker'),
        )
          ..headers['Authorization'] = 'Bearer $jwt'
          ..fields['user_id'] = userId
          ..files.add(await http.MultipartFile.fromPath('file', tmpFile.path));

        final streamed = await request.send().timeout(const Duration(seconds: 15));
        final resp = await http.Response.fromStream(streamed);

        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final identity = body['identity'] as String? ?? 'other';
          final confidence = (body['confidence'] as num?)?.toDouble() ?? 0.0;

          if (identity != 'unknown') {
            _speakerIdentityCache[speakerId] = identity;
            debugPrint('🔑 Speaker $speakerId identified as "$identity" (conf: ${confidence.toStringAsFixed(3)})');

            // Back-patch transcript entries that used the fallback
            bool patched = false;
            for (final entry in _fullTranscript) {
              if (entry['speakerId'] == speakerId || (entry['speaker'] == (speakerId == 0 ? 'user' : 'other') && entry['speakerId'] == null)) {
                entry['speaker'] = identity;
                patched = true;
              }
            }
            if (patched) notifyListeners();
          }
        }
      } finally {
        try { tmpFile.deleteSync(); } catch (_) {}
      }
    } catch (e) {
      debugPrint('⚠️ _identifySpeaker error for speaker $speakerId: $e');
    } finally {
      _pendingIdentification.remove(speakerId);
    }
  }

  static Uint8List _buildWavBytes(Uint8List pcm) {
    final b = ByteData(44 + pcm.length);
    void str(int offset, String s) {
      for (var i = 0; i < s.length; i++) b.setUint8(offset + i, s.codeUnitAt(i));
    }
    str(0, 'RIFF');
    b.setUint32(4, 36 + pcm.length, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, 1, Endian.little);
    b.setUint32(24, 16000, Endian.little);
    b.setUint32(28, 32000, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, pcm.length, Endian.little);
    for (var i = 0; i < pcm.length; i++) b.setUint8(44 + i, pcm[i]);
    return b.buffer.asUint8List();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    notifyListeners();
    debugPrint(_isMuted ? "🔇 Mic muted" : "🎙️ Mic unmuted");
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _isMuted = false;
    _isConnected = false;
    _speakerIdentityCache.clear();
    _pendingIdentification.clear();
    notifyListeners();

    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;

    await _recorder.stop();

    await _channel?.sink.close();
    _channel = null;
  }

  /// Save the buffered audio as a WAV file and the full transcript as a .txt
  /// file to the app documents directory.  Returns a map with 'audio' and
  /// 'transcript' paths, or null if there was nothing to save.
  Future<Map<String, String>?> saveSessionRecording(String sessionId) async {
    if (_fullTranscript.isEmpty && _audioBuffer.isEmpty) return null;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${dir.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      final base = '${recordingsDir.path}/$sessionId';
      final Map<String, String> paths = {};

      // Save WAV audio
      if (_audioBuffer.isNotEmpty) {
        final audioBytes = _audioBuffer.toBytes();
        final wavHeader = _buildWavHeader(audioBytes.length);
        final audioFile = File('$base.wav');
        final sink = audioFile.openWrite();
        sink.add(wavHeader);
        sink.add(audioBytes);
        await sink.close();
        _lastSavedAudioPath = audioFile.path;
        paths['audio'] = audioFile.path;
        debugPrint("✅ DeepgramService: Audio saved → ${audioFile.path}");
      }

      // Save timing JSON (for synchronized playback)
      if (_fullTranscript.isNotEmpty) {
        final timingFile = File('${base}_timing.json');
        await timingFile.writeAsString(jsonEncode(_fullTranscript));
        _lastSavedTimingPath = timingFile.path;
        paths['timing'] = timingFile.path;
        debugPrint("✅ DeepgramService: Timing saved → ${timingFile.path}");

        // Plain text transcript for export
        final lines = _fullTranscript.map((e) {
          final label = e['speaker'] == 'user' ? 'You' : 'Other';
          return '$label: ${e['text']}';
        }).join('\n');
        final txFile = File('${base}_transcript.txt');
        await txFile.writeAsString(lines);
        _lastSavedTranscriptPath = txFile.path;
        paths['transcript'] = txFile.path;
      }

      _audioBuffer.clear();
      _fullTranscript.clear();
      _audioElapsed = 0.0;

      return paths.isEmpty ? null : paths;
    } catch (e) {
      debugPrint("❌ DeepgramService: Failed to save recording: $e");
      return null;
    }
  }

  /// Build a minimal 44-byte WAV header for mono 16-bit PCM at 16 kHz.
  static Uint8List _buildWavHeader(int dataSize) {
    final b = ByteData(44);
    void str(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + dataSize, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);  // PCM fmt chunk size
    b.setUint16(20, 1, Endian.little);   // PCM format
    b.setUint16(22, 1, Endian.little);   // mono
    b.setUint32(24, 16000, Endian.little); // sample rate
    b.setUint32(28, 32000, Endian.little); // byte rate (16000 * 1 * 2)
    b.setUint16(32, 2, Endian.little);   // block align
    b.setUint16(34, 16, Endian.little);  // bits per sample
    str(36, 'data');
    b.setUint32(40, dataSize, Endian.little);
    return b.buffer.asUint8List();
  }

  void _attemptReconnect({required String serverUrl, required String jwt}) {
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
      if (!_intentionalDisconnect) connect(serverUrl: serverUrl, jwt: jwt);
    });
  }
}
