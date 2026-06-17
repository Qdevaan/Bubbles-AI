// Purpose: Fetches and caches the user's tracked communication mistakes from the mistakes table.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'suggestion_service.dart' show CancelToken;

class MistakeItem {
  final String id;
  final String category;
  final String snippet;
  final String? suggestion;
  final String ruleId;
  final String source;

  MistakeItem({
    required this.id,
    required this.category,
    required this.snippet,
    required this.ruleId,
    required this.source,
    this.suggestion,
  });

  factory MistakeItem.fromJson(Map<String, dynamic> j) => MistakeItem(
        id: j['id'].toString(),
        category: j['category'] as String,
        snippet: j['snippet'] as String,
        suggestion: j['suggestion'] as String?,
        ruleId: j['rule_id'] as String,
        source: j['source'] as String,
      );
}

class MistakeCheckResult {
  final int count;
  final Map<String, int> byCategory;
  final List<MistakeItem> items;
  final int latencyMs;

  MistakeCheckResult({
    required this.count,
    required this.byCategory,
    required this.items,
    required this.latencyMs,
  });

  factory MistakeCheckResult.fromJson(Map<String, dynamic> j) =>
      MistakeCheckResult(
        count: (j['count'] as num).toInt(),
        byCategory: (j['by_category'] as Map).map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        ),
        items: (j['items'] as List)
            .map((e) =>
                MistakeItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        latencyMs: (j['latency_ms'] as num).toInt(),
      );
}

class MistakeService {
  final String baseUrl;
  final String jwt;
  final Duration timeout;

  MistakeService(
    this.baseUrl,
    this.jwt, {
    this.timeout = const Duration(seconds: 4),
  });

  Future<MistakeCheckResult?> checkTurn({
    required String userId,
    required String sessionId,
    required String transcript,
    required CancelToken cancelToken,
  }) async {
    if (cancelToken.isCancelled) return null;
    final client = http.Client();
    try {
      final resp = await client
          .post(
            Uri.parse('$baseUrl/v1/check_user_turn'),
            headers: {
              'Authorization': 'Bearer $jwt',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'user_id': userId,
              'session_id': sessionId,
              'transcript': transcript,
            }),
          )
          .timeout(timeout);

      if (cancelToken.isCancelled) return null;
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is Map<String, dynamic>) {
        return MistakeCheckResult.fromJson(data);
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

  Future<List<MistakeItem>> listForSession({
    required String sessionId,
  }) async {
    final client = http.Client();
    try {
      final resp = await client.get(
        Uri.parse('$baseUrl/v1/user_mistakes?session_id=$sessionId'),
        headers: {'Authorization': 'Bearer $jwt'},
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final items = (data['items'] as List?) ?? [];
      return items
          .map((e) =>
              MistakeItem.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    } finally {
      client.close();
    }
  }
}
