// Purpose: Sends transcript chunks to the Wingman suggestion endpoint and caches the latest AI coaching tip.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SuggestionResult {
  final List<String> suggestions;
  final String kind; // 'draft' | 'final' | 'error'
  final int latencyMs;
  final String requestId;

  SuggestionResult({
    required this.suggestions,
    required this.kind,
    required this.latencyMs,
    required this.requestId,
  });

  factory SuggestionResult.fromJson(Map<String, dynamic> j) =>
      SuggestionResult(
        suggestions:
            (j['suggestions'] as List).map((e) => e.toString()).toList(),
        kind: j['kind'] as String,
        latencyMs: (j['latency_ms'] as num).toInt(),
        requestId: j['request_id'] as String,
      );
}

/// Cancel handle for an in-flight suggestion request. Mirrors dio's
/// `CancelToken` API so callers can await cancellation symmetrically.
class CancelToken {
  final Completer<void> _cancelled = Completer<void>();
  http.Client? _client;

  bool get isCancelled => _cancelled.isCompleted;

  void _attachClient(http.Client c) {
    _client = c;
  }

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
      _client?.close();
    }
  }

  Future<void> get whenCancelled => _cancelled.future;
}

class SuggestionService {
  final String baseUrl;
  final String jwt;
  final Duration timeout;

  SuggestionService(
    this.baseUrl,
    this.jwt, {
    this.timeout = const Duration(seconds: 2),
  });

  Future<SuggestionResult?> fetch({
    required String userId,
    required String sessionId,
    required String partnerUtterance,
    required String tone,
    required bool isDraft,
    required CancelToken cancelToken,
  }) async {
    if (cancelToken.isCancelled) return null;

    final client = http.Client();
    cancelToken._attachClient(client);

    try {
      final resp = await client
          .post(
            Uri.parse('$baseUrl/v1/suggest_reply'),
            headers: {
              'Authorization': 'Bearer $jwt',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'user_id': userId,
              'session_id': sessionId,
              'partner_utterance': partnerUtterance,
              'tone': tone,
              'is_draft': isDraft,
            }),
          )
          .timeout(timeout);

      if (cancelToken.isCancelled) return null;
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is Map<String, dynamic>) {
        return SuggestionResult.fromJson(data);
      }
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
