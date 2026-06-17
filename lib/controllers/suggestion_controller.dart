// Purpose: Suggestion controller — debounces transcript input and dispatches Wingman suggestion requests during live sessions.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/suggestion_service.dart';

class SuggestionController extends ChangeNotifier {
  final SuggestionService service;
  final String userId;
  final String sessionId;
  String tone;
  final Duration debounce;

  Timer? _debounceTimer;
  CancelToken? _inFlight;

  List<String> _suggestions = [];
  bool _isDraft = false;
  bool _loading = false;

  List<String> get suggestions => List.unmodifiable(_suggestions);
  bool get isDraft => _isDraft;
  bool get loading => _loading;

  SuggestionController({
    required this.service,
    required this.userId,
    required this.sessionId,
    required this.tone,
    this.debounce = const Duration(milliseconds: 400),
  });

  void onInterimTranscript(String text) {
    if (text.trim().length < 5) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => _fetch(text, isDraft: true));
  }

  void onFinalTranscript(String text) {
    if (text.trim().isEmpty) return;
    _debounceTimer?.cancel();
    _fetch(text, isDraft: false);
  }

  void clear() {
    _debounceTimer?.cancel();
    _inFlight?.cancel();
    _inFlight = null;
    _suggestions = [];
    _isDraft = false;
    _loading = false;
    notifyListeners();
  }

  Future<void> _fetch(String text, {required bool isDraft}) async {
    _inFlight?.cancel();
    final tok = CancelToken();
    _inFlight = tok;
    _loading = true;
    notifyListeners();

    final res = await service.fetch(
      userId: userId,
      sessionId: sessionId,
      partnerUtterance: text,
      tone: tone,
      isDraft: isDraft,
      cancelToken: tok,
    );

    if (tok.isCancelled || _inFlight != tok) return;
    _loading = false;

    if (res != null && res.suggestions.isNotEmpty) {
      _suggestions = res.suggestions;
      _isDraft = res.kind == 'draft';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _inFlight?.cancel();
    super.dispose();
  }
}
