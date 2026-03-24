import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dedicated state manager for the Consultant chat screen.
/// Extracts streaming, chat messages, drawer state, and session management
/// out of the screen widget into a proper ChangeNotifier provider.
class ConsultantProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

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
    AnalyticsService.instance.logAction(
      action: 'consultant_new_chat',
      entityType: 'consultant',
    );
  }

  // ── Load past chats for drawer ──
  Future<void> loadPastChats() async {
    if (_drawerLoading) return;
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    _drawerLoading = true;
    notifyListeners();

    try {
      final rows = List<Map<String, dynamic>>.from(
        await _supabase
            .from('consultant_logs')
            .select('session_id, question, query, created_at')
            .eq('user_id', user.id)
            .not('session_id', 'is', null)
            .order('created_at', ascending: true),
      );

      final Map<String, Map<String, dynamic>> seen = {};
      for (final r in rows) {
        final sid = r['session_id'] as String?;
        if (sid == null) continue;
        seen.putIfAbsent(
          sid,
          () => {
            'session_id': sid,
            'title': (r['question'] as String?) ?? (r['query'] as String?) ?? 'Chat',
            'created_at': r['created_at'] as String? ?? '',
          },
        );
      }

      final list = seen.values.toList()
        ..sort(
          (a, b) =>
              (b['created_at'] as String).compareTo(a['created_at'] as String),
        );

      _pastChats = list;
      _drawerLoading = false;
      _drawerLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('loadPastChats error: $e');
      _drawerLoading = false;
      notifyListeners();
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

    try {
      final rows = List<Map<String, dynamic>>.from(
        await _supabase
            .from('consultant_logs')
            .select('question, query, answer, response, created_at')
            .eq('session_id', sessionId)
            .eq('user_id', user.id)
            .order('created_at', ascending: true),
      );

      _currentSessionId = sessionId;
      for (final r in rows) {
        final q = (r['question'] as String?) ?? (r['query'] as String?);
        if (q != null) {
          _messages.add({"role": "user", "text": q});
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
      AnalyticsService.instance.logAction(
        action: 'consultant_chat_loaded',
        entityType: 'consultant',
        entityId: sessionId,
      );
    } catch (e) {
      debugPrint('loadChatById error: $e');
      _loadingChat = false;
      notifyListeners();
    }
  }

  // ── Send message via SSE streaming ──
  /// [onFirstToken] fires when the first AI token arrives (useful for voice mode).
  /// [onComplete] fires with the full response text when streaming finishes.
  Future<void> sendMessage(
    String text,
    ApiService api, {
    String tone = 'casual',
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

    AnalyticsService.instance.logAction(
      action: 'consultant_message_sent',
      entityType: 'consultant',
      entityId: _currentSessionId,
      details: {'tone': tone},
    );

    final buf = StringBuffer();
    bool firstToken = true;

    try {
      final stream = api.askConsultantStream(
        user.id,
        text,
        sessionId: _currentSessionId,
        mode: tone,
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
