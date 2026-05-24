import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/confidence_heuristic.dart';

/// Per-session container for the F4 live confidence meter:
///   - rolling 8 s window fed by every STT chunk
///   - per-turn snapshot list captured at user-turn boundaries
///   - fire-and-forget POST on session end
///
/// Lives for the lifetime of one active session and is reset between
/// sessions via [reset].
class ConfidenceProvider extends ChangeNotifier {
  ConfidenceProvider(this._api);

  final ApiService _api;
  final ConfidenceWindow _window = ConfidenceWindow();
  final List<Map<String, dynamic>> _snapshots = [];

  double _score = 1.0;
  int _nextTurnIndex = 0;

  double get score => _score;
  int get capturedTurns => _snapshots.length;
  List<Map<String, dynamic>> get snapshots =>
      List.unmodifiable(_snapshots);

  /// Reset everything (call when a new session starts).
  void reset() {
    _window.clear();
    _snapshots.clear();
    _score = 1.0;
    _nextTurnIndex = 0;
    notifyListeners();
  }

  /// Feed an incremental transcript chunk from STT. Recomputes the score
  /// and notifies listeners. Empty chunks are ignored.
  void onTranscriptChunk(String chunk) {
    if (chunk.trim().isEmpty) return;
    _window.addChunk(chunk);
    final next = _window.currentScore();
    if ((next - _score).abs() < 0.005) return;
    _score = next;
    notifyListeners();
  }

  /// Snapshot the current meter value for a user turn. Server expects
  /// `turn_index` to be 0-based and monotonically increasing.
  void captureTurn() {
    _snapshots.add({
      'turn_index': _nextTurnIndex,
      'score': double.parse(_score.toStringAsFixed(4)),
    });
    _nextTurnIndex += 1;
  }

  /// Fire-and-forget POST `/v1/sessions/{id}/confidence`. Retries once
  /// on network error. Never throws — failure is logged and dropped per
  /// the F4 spec.
  Future<void> flushToServer(String sessionId) async {
    if (_snapshots.isEmpty) return;
    final payload = List<Map<String, dynamic>>.from(_snapshots);
    final code =
        await _api.setSessionConfidence(sessionId: sessionId, items: payload);
    // Network error: retry exactly once.
    if (code == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _api.setSessionConfidence(sessionId: sessionId, items: payload);
    }
  }
}
