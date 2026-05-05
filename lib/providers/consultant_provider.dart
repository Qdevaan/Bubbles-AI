import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../repositories/sessions_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dedicated state manager for the Consultant chat screen.
/// Extracts streaming, chat messages, drawer state, and session management
/// out of the screen widget into a proper ChangeNotifier provider.
class ConsultantProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  SessionsRepository? _repository;

  void setRepository(SessionsRepository repo) => _repository = repo;

  // ── Current chat ──
  String? _currentSessionId;
  String? get currentSessionId => _currentSessionId;

  final List<Map<String, String>> _messages = [];
  List<Map<String, String>> get messages => List.unmodifiable(_messages);

  bool _loading = false;
  bool get loading => _loading;

  // ── Drawer / past chats ──
  List<Map<String, dynamic>> _pastChats = [];
  List<Map<String, dynamic>> get pastChats => _pastChats;

  bool _drawerLoading = false;
  bool get drawerLoading => _drawerLoading;

  bool _drawerLoaded = false;
  bool get drawerLoaded => _drawerLoaded;

  bool _loadingChat = false;
  bool get loadingChat => _loadingChat;

  ConsultantProvider() {
    _messages.add({"role": "ai", "text": "How can I help you today?"});
  }

  void setWelcomeMessage(String message) {
    if (_messages.isNotEmpty && _messages.first['role'] == 'ai') {
      _messages[0] = {"role": "ai", "text": message};
    }
    notifyListeners();
  }

  // ── New / clear chat ──
  void newChat(String welcomeMessage) {
    _currentSessionId = null;
    _messages
      ..clear()
      ..add({"role": "ai", "text": welcomeMessage});
    notifyListeners();
  }

  // ── Load past chats for drawer ──
  Future<void> loadPastChats() async {
    if (_drawerLoading) return;
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    _drawerLoading = true;
    notifyListeners();

    if (_repository != null) {
      try {
        final result = await _repository!.getConsultantSessions(user.id);
        _pastChats = result.data ?? [];
        _drawerLoading = false;
        _drawerLoaded = true;
        notifyListeners();
      } catch (e) {
        debugPrint('loadPastChats repo error: $e');
        _drawerLoading = false;
        notifyListeners();
      }
    }
  }

  // ── Load messages for a selected past chat ──
  Future<void> loadChatById(String sessionId) async {
    if (_loadingChat) return;
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    _loadingChat = true;
    _messages.clear();
    notifyListeners();

    if (_repository != null) {
      try {
        final result = await _repository!.getSessionLogs(sessionId, true, user.id);
        final rows = result.data ?? [];
        _currentSessionId = sessionId;
        for (final r in rows) {
          final q = (r['question'] as String?) ?? (r['query'] as String?);
          final sourceScreen = r['source_screen'] as String?;
          if (q != null) {
            final msg = <String, String>{"role": "user", "text": q};
            if (sourceScreen != null) msg['source_screen'] = sourceScreen;
            _messages.add(msg);
          }
          final a = (r['answer'] as String?) ?? (r['response'] as String?);
          if (a != null) {
            _messages.add({"role": "ai", "text": a});
          }
        }
        if (_messages.isEmpty) {
          _messages.add({
            "role": "ai",
            "text": "This conversation appears to be empty.",
          });
        }
        _loadingChat = false;
        notifyListeners();
      } catch (e) {
        debugPrint('loadChatById repo error: $e');
        _loadingChat = false;
        notifyListeners();
      }
    }
  }

  // ── Send message via SSE streaming ──
  /// [onFirstToken] fires when the first AI token arrives (useful for voice mode).
  /// [onComplete] fires with the full response text when streaming finishes.
  Future<void> sendMessage(
    String text,
    ApiService api, {
    String tone = 'casual',
    String? mood,
    void Function()? onFirstToken,
    void Function(String fullResponse)? onComplete,
  }) async {
    if (text.isEmpty || _loading || _loadingChat) return;

    final user = AuthService.instance.currentUser;
    if (user == null) return;

    final time = _nowTime();
    _messages.add({"role": "user", "text": text, "time": time});
    _loading = true;
    notifyListeners();


    final buf = StringBuffer();
    bool firstToken = true;

    try {
      final stream = api.askConsultantStream(
        user.id,
        text,
        sessionId: _currentSessionId,
        mode: 'consultant',
        persona: tone,
        mood: mood,
        onSessionCreated: (sid) {
          _currentSessionId = sid;
          _drawerLoaded = false;
          notifyListeners();
        },
      );

      final aiTime = _nowTime();
      await for (final token in stream) {
        buf.write(token);
        if (firstToken) {
          _loading = false;
          _messages.add({
            "role": "ai",
            "text": buf.toString(),
            "streaming": "true",
            "time": aiTime,
          });
          firstToken = false;
          onFirstToken?.call();
        } else {
          _messages.last = {
            "role": "ai",
            "text": buf.toString(),
            "streaming": "true",
            "time": aiTime,
          };
        }
        notifyListeners();
      }

      if (_messages.isNotEmpty && _messages.last['streaming'] == 'true') {
        _messages.last = {
          "role": "ai",
          "text": buf.toString(),
          "time": _messages.last['time'] ?? _nowTime(),
        };
      }
      _loading = false;
      notifyListeners();
      
      // Mark onboarding
      await AuthService.instance.updateOnboardingProgress({'first_consultant': true});
      
      onComplete?.call(buf.toString());
    } catch (e) {
      if (firstToken) {
        _messages.add({
          "role": "ai",
          "text": "Error connecting to consultant: $e",
          "time": _nowTime(),
        });
      } else {
        _messages.last = {
          "role": "ai",
          "text": buf.isEmpty ? "Error: $e" : buf.toString(),
          "time": _messages.last['time'] ?? _nowTime(),
        };
      }
      _loading = false;
      notifyListeners();
      onComplete?.call(buf.toString());
    }
  }

  String get lastAiResponse {
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i]['role'] == 'ai') return _messages[i]['text'] ?? '';
    }
    return '';
  }

  String _nowTime() {
    final dt = DateTime.now();
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$hour12:$m $period';
  }
}
