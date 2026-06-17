// Purpose: Central HTTP client for the FastAPI backend — handles voice, sessions, Consultant, Wingman, gamification, and graph endpoints.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/persona.dart';
import 'connection_service.dart';
import 'auth_service.dart';

class ApiService {
  final ConnectionService _connectionService;

  ApiService(this._connectionService);

  String get _baseUrl => _connectionService.serverUrl;
  bool get isConnected => _connectionService.isConnected;

  // Retry with exponential backoff
  static const int _maxRetries = 3;
  static const Duration _baseDelay = Duration(milliseconds: 500);

  // Retry with exponential backoff — only retries on network/timeout errors
  Future<T> _withRetry<T>(
    Future<T> Function() action, {
    int? maxRetries,
  }) async {
    final retries = maxRetries ?? _maxRetries;
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        return await action();
      } on TimeoutException {
        if (attempt == retries) rethrow;
      } on http.ClientException {
        if (attempt == retries) rethrow;
      } catch (e) {
        // Don't retry on non-network errors (e.g. FormatException)
        if (e is! TimeoutException && e is! http.ClientException) rethrow;
      }
      final delay = _baseDelay * pow(2, attempt).toInt();
      final jitter = Duration(
        milliseconds: Random().nextInt(delay.inMilliseconds ~/ 2 + 1),
      );
      await Future.delayed(delay + jitter);
      debugPrint('Retry attempt ${attempt + 1}/$retries');
    }
    throw TimeoutException('All $retries retries exhausted');
  }

  // Auth Header Builder
  // Builds auth headers with the current Supabase JWT; safe to call when logged out
  Future<Map<String, String>> _authHeaders({
    bool isMultipart = false,
  }) async {
    final headers = <String, String>{
      if (!isMultipart) 'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
    };

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null && session.accessToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
    } catch (e) {
      debugPrint('⚠️ Could not attach Bearer token: $e');
    }

    return headers;
  }

  Future<Map<String, dynamic>?> getToken(String userId, {String? roomName}) async {
    if (_baseUrl.isEmpty) return null;
    try {
      return await _withRetry(() async {
        final body = {'userId': userId};
        if (roomName != null && roomName.isNotEmpty) {
          body['roomName'] = roomName;
        }
        final response = await http
            .post(
              Uri.parse('$_baseUrl/v1/getToken'),
              headers: await _authHeaders(),
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
        return null;
      });
    } catch (e) {
      debugPrint("Token Error: $e");
    }
    return null;
  }

  // Voice enrollment
  /// Uploads audio to enroll the user's voice signature.
  Future<String> enrollVoice({
    required String userId,
    required String userName,
    required String audioPath,
  }) async {
    if (_baseUrl.isEmpty) throw Exception('Server URL not set.');

    final uri = Uri.parse('$_baseUrl/v1/enroll');

    try {
      final request = http.MultipartRequest('POST', uri);
      // Inject auth headers (without Content-Type for multipart)
      final headers = await _authHeaders(isMultipart: true);
      request.headers.addAll(headers);
      request.fields['user_id'] = userId;
      request.fields['user_name'] = userName;
      request.files.add(await http.MultipartFile.fromPath('file', audioPath));

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw Exception(
          'Server error ${response.statusCode}: ${response.body}',
        );
      }

      final status = await checkEnrollmentStatus(userId);
      if (status == null) {
        throw Exception(
          'Enrollment uploaded but embedding not found in database.',
        );
      }
      AuthService.instance.updateOnboardingProgress({'voice_enrolled': true});
      return status;
    } catch (e) {
      throw Exception('Enrollment failed: $e');
    }
  }

  Future<String?> checkEnrollmentStatus(String userId) async {
    try {
      final res = await Supabase.instance.client
          .from('voice_enrollments')
          .select('updated_at')
          .eq('user_id', userId)
          .maybeSingle();
      return res?['updated_at'] as String?;
    } catch (e) {
      debugPrint('checkEnrollmentStatus error: $e');
      return null;
    }
  }

  // Live Wingman — short audio chunk processing
  Future<Map<String, dynamic>> processAudioChunk(String filePath) async {
    if (_baseUrl.isEmpty)
      return {"transcript": "", "suggestion": "No Server URL"};

    try {
      var uri = Uri.parse("$_baseUrl/v1/process_audio");
      var request = http.MultipartRequest('POST', uri);
      final headers = await _authHeaders(isMultipart: true);
      request.headers.addAll(headers);
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 15),
      );
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        debugPrint("Server Error (${response.statusCode}): ${response.body}");
        return {"transcript": "", "suggestion": ""};
      }
    } catch (e) {
      debugPrint("API Chunk Error: $e");
      return {"transcript": "", "suggestion": ""};
    }
  }

  // Session saving — uploads the transcript for vector embedding
  Future<bool> saveSession(
    String userId,
    List<Map<String, dynamic>> logs,
  ) async {
    if (_baseUrl.isEmpty) return false;

    try {
      return await _withRetry(() async {
        var uri = Uri.parse("$_baseUrl/v1/save_session");
        String fullTranscript = logs
            .map((l) => "${l['speaker']}: ${l['text']}")
            .join("\n");

        var response = await http
            .post(
              uri,
              headers: await _authHeaders(),
              body: jsonEncode({
                "user_id": userId,
                "transcript": fullTranscript,
                "logs": logs,
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          AuthService.instance.updateOnboardingProgress({'first_wingman': true});
          return true;
        }
        return false;
      });
    } catch (e) {
      debugPrint("Save Session Error: $e");
      return false;
    }
  }

  // Consultant — non-streaming ask
  Future<String> askConsultant(String userId, String question) async {
    if (_baseUrl.isEmpty) return "Please connect to the server first.";

    try {
      return await _withRetry(() async {
        // Force JSON mode — without stream=false the server defaults to an
        // SSE StreamingResponse and jsonDecode below would throw.
        var uri = Uri.parse("$_baseUrl/v1/ask_consultant?stream=false");
        var response = await http
            .post(
              uri,
              headers: await _authHeaders(),
              body: jsonEncode({"question": question}),
            )
            .timeout(const Duration(seconds: 60));

        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          AuthService.instance.updateOnboardingProgress({'first_consultant': true});
          return data['answer'] as String;
        }
        return "Brain Error: ${response.statusCode}";
      });
    } catch (e) {
      return "Connection Error: $e";
    }
  }

  // Wingman (text) — fire-and-forget suggestion with live coaching timeout
  Future<String?> sendTranscriptToWingman(
    String userId,
    String transcript, {
    String? sessionId,
    String speakerRole = 'others',
    String mode = 'live_wingman',
    String persona = 'casual',
  }) async {
    if (_baseUrl.isEmpty) return null;

    try {
      return await _withRetry(() async {
        var uri = Uri.parse("$_baseUrl/v1/process_transcript_wingman");
        final body = <String, dynamic>{
          "user_id": userId,
          "transcript": transcript,
          "speaker_role": speakerRole,
          "mode": mode,
          "persona": persona,
          if (sessionId != null) "session_id": sessionId,
        };
        var response = await http
            .post(
              uri,
              headers: await _authHeaders(),
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 8)); // live coaching timeout

        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          return data['advice'] as String?;
        }
        return null;
      }, maxRetries: 0); // fail fast — stale retries are useless for live coaching
    } catch (e) {
      debugPrint("Wingman API Error: $e");
    }
    return null;
  }

  // Session lifecycle
  Future<String?> createLiveSession(
      String userId, {
      String mode = "live_wingman",
      String? targetEntityId,
      bool isEphemeral = false,
      bool isMultiplayer = false,
      String persona = "casual",
  }) async {
    if (_baseUrl.isEmpty) return null;
    try {
      return await _withRetry(() async {
        final body = <String, dynamic>{
          "user_id": userId,
          "mode": mode,
          "is_ephemeral": isEphemeral,
          "is_multiplayer": isMultiplayer,
          "persona": persona,
        };
        if (targetEntityId != null) {
          body["target_entity_id"] = targetEntityId;
        }

        final res = await http
            .post(
              Uri.parse("$_baseUrl/v1/start_session"),
              headers: await _authHeaders(),
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          AuthService.instance.updateOnboardingProgress({'first_wingman': true});
          return jsonDecode(res.body)['session_id'] as String?;
        }
        return null;
      });
    } catch (e) {
      debugPrint("createLiveSession error: $e");
    }
    return null;
  }

  Future<void> endLiveSession(String sessionId, String userId) async {
    if (_baseUrl.isEmpty) return;
    try {
      await _withRetry(() async {
        await http
            .post(
              Uri.parse("$_baseUrl/v1/end_session"),
              headers: await _authHeaders(),
              body: jsonEncode({"session_id": sessionId, "user_id": userId}),
            )
            .timeout(const Duration(seconds: 60));
      });
    } catch (e) {
      debugPrint("endLiveSession error: $e");
    }
  }

  // Streaming consultant (SSE) — tokens from /ask_consultant_stream
  Stream<String> askConsultantStream(
    String userId,
    String question, {
    String? sessionId,
    String mode = 'consultant',
    String persona = 'casual',
    String? mood,
    void Function(String sessionId)? onSessionCreated,
  }) async* {
    if (_baseUrl.isEmpty) {
      yield 'Please connect to the server first.';
      return;
    }
    final client = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse("$_baseUrl/v1/ask_consultant?stream=true"),
      );

      // Inject Bearer token on SSE request too
      final headers = await _authHeaders();
      headers['Accept'] = 'text/event-stream';
      request.headers.addAll(headers);
      // Server derives the user from the JWT and accepts only these fields
      // (ConsultantRequest: question, persona, session_id). user_id/mode/mood
      // are forbidden extras — sending them yields HTTP 422.
      request.body = jsonEncode({
        'question': question,
        'persona': persona,
        if (sessionId != null) 'session_id': sessionId,
      });

      final streamedResponse = await client
          .send(request)
          .timeout(const Duration(seconds: 60));
      if (streamedResponse.statusCode != 200) {
        yield 'Server error: ${streamedResponse.statusCode}';
        return;
      }

      // Improved SSE parser
      // Accumulates raw bytes into a string buffer and processes complete SSE
      // events delimited by double-newlines (\n\n or \r\n\r\n), which is the
      // RFC 8895 standard. This is robust against packet-splitting.
      final StringBuffer buffer = StringBuffer();

      // utf8.decoder transformer handles multi-byte chars split across chunks
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        buffer.write(chunk);
        final raw = buffer.toString();

        // SSE events are separated by double newlines
        // Normalize \r\n to \n for consistent processing
        final normalized = raw.replaceAll('\r\n', '\n');

        // Split on double-newline (event boundaries)
        final events = normalized.split('\n\n');

        // The last element may be an incomplete event — keep it in the buffer
        buffer.clear();
        if (!normalized.endsWith('\n\n')) {
          // Last chunk is incomplete — put it back
          buffer.write(events.removeLast());
        } else {
          events.removeLast(); // remove empty string after final \n\n
        }

        // Process each complete SSE event
        for (final event in events) {
          if (event.trim().isEmpty) continue;

          // An SSE event has an `event:` name line and a `data:` JSON line.
          // Server contract (bubbles.ai.streaming.sse_from_chunks):
          //   event: token  / data: {"t": "<text>"}
          //   event: done   / data: {"finish": ..., "prompt_tokens": ...}
          //   event: ping   / data: {"t": "hb"}        (heartbeat — ignore)
          //   event: error  / data: {"error": "<msg>"}
          String? eventName;
          String? dataStr;
          for (final line in event.split('\n')) {
            final trimmed = line.trim();
            if (trimmed.startsWith('event:')) {
              eventName = trimmed.substring(6).trim();
            } else if (trimmed.startsWith('data:')) {
              dataStr = trimmed.substring(5).trim(); // strip 'data:'
            }
          }
          if (dataStr == null || dataStr.isEmpty || dataStr == '[DONE]') {
            continue;
          }
          if (eventName == 'ping') continue; // heartbeat keep-alive

          try {
            final parsed = jsonDecode(dataStr) as Map<String, dynamic>;
            if (eventName == 'done' || parsed.containsKey('finish')) {
              AuthService.instance
                  .updateOnboardingProgress({'first_consultant': true});
              final sid = parsed['session_id'] as String?;
              if (sid != null && onSessionCreated != null) {
                onSessionCreated(sid);
              }
              return;
            }
            if (parsed['error'] != null) {
              yield '\n[Error: ${parsed['error']}]';
              return;
            }
            // Token chunk — server keys the text under "t".
            final token = parsed['t'] ?? parsed['token'];
            if (token != null) {
              yield token as String;
            }
          } catch (_) {
            // Malformed JSON — skip silently
          }
        }
      }
    } catch (e) {
      yield '\n[Connection error: $e]';
    } finally {
      client.close();
    }
  }

  // Ask about a named entity — returns an AI-generated summary of what we know
  Future<String> askAboutEntity(String userId, String entityName) async {
    if (_baseUrl.isEmpty) return 'Server not connected.';
    try {
      final res = await http
          .post(
            Uri.parse("$_baseUrl/v1/ask_entity"),
            headers: await _authHeaders(),
            body: jsonEncode({"user_id": userId, "entity_name": entityName}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['answer'] as String? ?? '—';
      }
      return 'Error: ${res.statusCode}';
    } catch (e) {
      return 'Connection error: $e';
    }
  }

  // Save feedback (thumbs/star/text) on a session_log or consultant_log
  Future<bool> saveFeedback({
    required String userId,
    String? sessionId,
    String? sessionLogId,
    String? consultantLogId,
    required String feedbackType, // 'thumbs' | 'star' | 'text'
    int? value,
    String? comment,
  }) async {
    if (_baseUrl.isEmpty) return false;
    try {
      final body = <String, dynamic>{
        'user_id': userId,
        'feedback_type': feedbackType,
      };
      if (sessionId != null) body['session_id'] = sessionId;
      if (sessionLogId != null) body['session_log_id'] = sessionLogId;
      if (consultantLogId != null) body['consultant_log_id'] = consultantLogId;
      if (value != null) body['value'] = value;
      if (comment != null && comment.isNotEmpty) body['comment'] = comment;

      final res = await http
          .post(
            Uri.parse('$_baseUrl/v1/save_feedback'),
            headers: await _authHeaders(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('saveFeedback error: $e');
      return false;
    }
  }

  // Session analytics — returns pre-computed data for a session (null if not ready)
  Future<Map<String, dynamic>?> getSessionAnalytics(String sessionId) async {
    if (_baseUrl.isEmpty) return null;
    try {
      final res = await http
          .get(
            Uri.parse('$_baseUrl/v1/session_analytics/$sessionId'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('getSessionAnalytics error: $e');
      return null;
    }
  }

  // Coaching report — lazily generated on first request
  Future<Map<String, dynamic>?> getCoachingReport(String sessionId) async {
    if (_baseUrl.isEmpty) return null;
    try {
      final res = await http
          .get(
            Uri.parse('$_baseUrl/v1/coaching_report/$sessionId'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('getCoachingReport error: $e');
      return null;
    }
  }

  // Knowledge graph export
  Future<Map<String, dynamic>?> getGraphExport(String userId) async {
    if (!_connectionService.isConnected) return null;
    try {
      final res = await http
          .get(
            Uri.parse('${_connectionService.serverUrl}/v1/graph_export/$userId'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('getGraphExport error: $e');
      return null;
    }
  }

  // Voice command parsing
  Future<Map<String, dynamic>?> parseVoiceCommand(
    String userId,
    String command,
  ) async {
    if (!_connectionService.isConnected) return null;
    final url = Uri.parse("${_connectionService.serverUrl}/v1/voice_command");
    try {
      final response = await http
          .post(
            url,
            headers: await _authHeaders(),
            body: jsonEncode({'user_id': userId, 'command': command}),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Voice command parse error: $e');
      return null;
    }
  }

  // Gamification & quests
  Future<Map<String, dynamic>?> getGamification(String userId) async {
    if (!_connectionService.isConnected) return null;
    try {
      final res = await http
          .get(
            Uri.parse('${_connectionService.serverUrl}/v1/gamification/$userId'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('getGamification error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getQuests(String userId) async {
    if (!_connectionService.isConnected) return null;
    try {
      final res = await http
          .get(
            Uri.parse('${_connectionService.serverUrl}/v1/quests/$userId'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('getQuests error: $e');
      return null;
    }
  }

  /// Submit an answer for a question_set quest.
  Future<Map<String, dynamic>?> submitQuestAnswer({
    required String userId,
    required String userQuestId,
    required String questionId,
    required String answer,
  }) async {
    if (!_connectionService.isConnected) return null;
    try {
      final res = await http
          .post(
            Uri.parse('${_connectionService.serverUrl}/v1/quests/$userId/$userQuestId/answer'),
            headers: await _authHeaders(),
            body: jsonEncode({'question_id': questionId, 'answer': answer}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      debugPrint('submitQuestAnswer non-200: ${res.statusCode} ${res.body}');
      return null;
    } catch (e) {
      debugPrint('submitQuestAnswer error: $e');
      return null;
    }
  }

  /// Attach a session to a conversation quest.
  Future<Map<String, dynamic>?> attachQuestSession({
    required String userId,
    required String userQuestId,
    required String sessionId,
  }) async {
    if (!_connectionService.isConnected) return null;
    try {
      final res = await http
          .post(
            Uri.parse('${_connectionService.serverUrl}/v1/quests/$userId/$userQuestId/attach_session'),
            headers: await _authHeaders(),
            body: jsonEncode({'session_id': sessionId}),
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      debugPrint('attachQuestSession non-200: ${res.statusCode} ${res.body}');
      return null;
    } catch (e) {
      debugPrint('attachQuestSession error: $e');
      return null;
    }
  }

  /// Fetch the reward catalog with affordability/ownership flags.
  Future<Map<String, dynamic>?> getRewards(String userId) async {
    if (!_connectionService.isConnected) return null;
    try {
      final res = await http
          .get(
            Uri.parse('${_connectionService.serverUrl}/v1/rewards/$userId'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      debugPrint('getRewards non-200: ${res.statusCode}');
      return null;
    } catch (e) {
      debugPrint('getRewards error: $e');
      return null;
    }
  }

  /// Fetch the global leaderboard for the given period.
  Future<Map<String, dynamic>?> getLeaderboard({
    String period = 'all',
    int limit = 25,
  }) async {
    if (!_connectionService.isConnected) return null;
    try {
      final res = await http
          .get(
            Uri.parse(
                '${_connectionService.serverUrl}/v1/leaderboard?period=$period&limit=$limit'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      debugPrint('getLeaderboard non-200: ${res.statusCode}');
      return null;
    } catch (e) {
      debugPrint('getLeaderboard error: $e');
      return null;
    }
  }

  /// Toggle leaderboard visibility.
  Future<bool> setLeaderboardOptIn({
    required String userId,
    required bool optIn,
  }) async {
    if (!_connectionService.isConnected) return false;
    try {
      final res = await http
          .post(
            Uri.parse(
                '${_connectionService.serverUrl}/v1/leaderboard/$userId/opt_in'),
            headers: await _authHeaders(),
            body: jsonEncode({'opt_in': optIn}),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('setLeaderboardOptIn error: $e');
      return false;
    }
  }

  /// Redeem a reward. Returns the new balance on success or a string error.
  Future<({Map<String, dynamic>? data, String? error})> redeemReward({
    required String userId,
    required String rewardId,
  }) async {
    if (!_connectionService.isConnected) {
      return (data: null, error: 'Server offline');
    }
    try {
      final res = await http
          .post(
            Uri.parse('${_connectionService.serverUrl}/v1/rewards/$userId/redeem'),
            headers: await _authHeaders(),
            body: jsonEncode({'reward_id': rewardId}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return (data: jsonDecode(res.body) as Map<String, dynamic>, error: null);
      }
      String? msg;
      try {
        msg = (jsonDecode(res.body) as Map)['detail'] as String?;
      } catch (_) {}
      return (data: null, error: msg ?? 'Redeem failed (${res.statusCode})');
    } catch (e) {
      debugPrint('redeemReward error: $e');
      return (data: null, error: 'Network error');
    }
  }

  // Performance summary for the adaptive gamification engine
  Future<Map<String, dynamic>?> getPerformanceSummary(String userId) async {
    if (!_connectionService.isConnected) return null;
    try {
      final res = await http
          .get(
            Uri.parse('${_connectionService.serverUrl}/v1/performance_summary/$userId'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('getPerformanceSummary error: $e');
      return null;
    }
  }

  // Graph query engine — NL questions about graph entities
  Future<Map<String, dynamic>> askGraphQuery(
    String userId,
    String query, {
    String? sessionId,
    List<Map<String, dynamic>>? graphEntities,
  }) async {
    if (!_connectionService.isConnected) {
      return {'answer': 'Server is offline. Connect to get AI insights.', 'session_id': null};
    }
    try {
      final hasEntities = graphEntities != null && graphEntities.isNotEmpty;
      // The /v1/ask endpoint (ConsultantRequest) is strict: it accepts only
      // `question`, `persona`, `session_id` and rejects extras with HTTP 422.
      // So we fold the knowledge-graph grounding + entities into the question
      // text itself rather than sending separate fields.
      final question = hasEntities
          ? 'Answer ONLY using the knowledge-graph entities and relationships '
              'below — do not use prior knowledge. If the answer is not supported '
              'by them, say so and suggest the closest related entity. Cite entity '
              'labels in your reply.\n\n'
              'Entities:\n${jsonEncode(graphEntities)}\n\n'
              'Question: $query'
          : query;
      final body = <String, dynamic>{
        'question': question,
        if (sessionId != null) 'session_id': sessionId,
      };
      final res = await http
          .post(
            Uri.parse('$_baseUrl/v1/ask'),
            headers: await _authHeaders(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return {
          'answer': data['answer'] as String? ?? data['response'] as String? ?? 'No answer available.',
          'session_id': data['session_id'] as String?,
        };
      }
      return {'answer': 'Could not get an answer right now (${res.statusCode}).', 'session_id': null};
    } catch (e) {
      debugPrint('askGraphQuery error: $e');
      return {'answer': 'Error: $e', 'session_id': null};
    }
  }

  // Persona (role-aware AI)
  Future<Map<String, dynamic>?> getMyPersona() async {
    if (_baseUrl.isEmpty) {
      throw Exception('Server URL not set.');
    }
    final res = await http
        .get(
          Uri.parse('$_baseUrl/v1/me/persona'),
          headers: await _authHeaders(),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    if (res.statusCode == 404) {
      return null;
    }
    throw Exception('getMyPersona failed: ${res.statusCode} ${res.body}');
  }

  Future<Map<String, dynamic>> upsertMyPersona(PersonaUpdate update) async {
    if (_baseUrl.isEmpty) {
      throw Exception('Server URL not set.');
    }
    final res = await http
        .put(
          Uri.parse('$_baseUrl/v1/me/persona'),
          headers: await _authHeaders(),
          body: jsonEncode(update.toJson()),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('upsertMyPersona failed: ${res.statusCode} ${res.body}');
  }

  Future<void> setSessionContext(
    String sessionId, {
    required String scenario,
    String roleMode = 'default',
    String? notes,
  }) async {
    if (_baseUrl.isEmpty) {
      throw Exception('Server URL not set.');
    }
    final body = <String, dynamic>{
      'scenario': scenario,
      'role_mode': roleMode,
      if (notes != null) 'notes': notes,
    };
    final res = await http
        .post(
          Uri.parse('$_baseUrl/v1/sessions/$sessionId/context'),
          headers: await _authHeaders(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('setSessionContext failed: ${res.statusCode} ${res.body}');
    }
  }

  // F2 — Drill cards

  Future<Map<String, dynamic>?> getDrillsQueue({
    int limit = 20,
    int offset = 0,
    bool includeUpcoming = false,
  }) async {
    if (_baseUrl.isEmpty) return null;
    final uri = Uri.parse('$_baseUrl/v1/drills/queue').replace(
      queryParameters: {
        'limit': '$limit',
        'offset': '$offset',
        'include_upcoming': includeUpcoming ? 'true' : 'false',
      },
    );
    try {
      final res = await http
          .get(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      debugPrint('getDrillsQueue ${res.statusCode}: ${res.body}');
      return null;
    } catch (e) {
      debugPrint('getDrillsQueue error: $e');
      return null;
    }
  }

  /// Returns `(data, statusCode, retryAfterSeconds)`. `data` is null on
  /// non-200; caller branches on `statusCode` (404/403/409/429/5xx).
  Future<({Map<String, dynamic>? data, int statusCode, int? retryAfter})>
      reviewDrill({
    required String cardId,
    required String result, // "correct" | "wrong"
  }) async {
    if (_baseUrl.isEmpty) {
      return (data: null, statusCode: 0, retryAfter: null);
    }
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/v1/drills/$cardId/review'),
            headers: await _authHeaders(),
            body: jsonEncode({'result': result}),
          )
          .timeout(const Duration(seconds: 15));
      final retry = int.tryParse(res.headers['retry-after'] ?? '');
      if (res.statusCode == 200) {
        return (
          data: jsonDecode(res.body) as Map<String, dynamic>,
          statusCode: 200,
          retryAfter: retry,
        );
      }
      return (data: null, statusCode: res.statusCode, retryAfter: retry);
    } catch (e) {
      debugPrint('reviewDrill error: $e');
      return (data: null, statusCode: 0, retryAfter: null);
    }
  }

  Future<({Map<String, dynamic>? data, int statusCode})> retireDrill(
    String cardId,
  ) async {
    if (_baseUrl.isEmpty) return (data: null, statusCode: 0);
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/v1/drills/$cardId/retire'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return (
          data: jsonDecode(res.body) as Map<String, dynamic>,
          statusCode: 200,
        );
      }
      return (data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('retireDrill error: $e');
      return (data: null, statusCode: 0);
    }
  }

  // F3 — Dashboard

  Future<({Map<String, dynamic>? data, int statusCode})> getDashboard({
    String range = '30d',
  }) async {
    if (_baseUrl.isEmpty) return (data: null, statusCode: 0);
    final uri = Uri.parse('$_baseUrl/v1/dashboard')
        .replace(queryParameters: {'range': range});
    try {
      final res = await http
          .get(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        return (
          data: jsonDecode(res.body) as Map<String, dynamic>,
          statusCode: 200,
        );
      }
      debugPrint('getDashboard ${res.statusCode}: ${res.body}');
      return (data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('getDashboard error: $e');
      return (data: null, statusCode: 0);
    }
  }

  // F1 — Scenarios

  Future<List<Map<String, dynamic>>?> getScenarios({
    String status = 'suggested',
    int limit = 20,
    int offset = 0,
  }) async {
    if (_baseUrl.isEmpty) return null;
    final uri = Uri.parse('$_baseUrl/v1/scenarios').replace(
      queryParameters: {
        'status': status,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    try {
      final res = await http
          .get(uri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body is List) {
          return [
            for (final s in body)
              if (s is Map<String, dynamic>) s,
          ];
        }
        if (body is Map<String, dynamic> && body['scenarios'] is List) {
          return [
            for (final s in (body['scenarios'] as List))
              if (s is Map<String, dynamic>) s,
          ];
        }
      }
      debugPrint('getScenarios ${res.statusCode}: ${res.body}');
      return null;
    } catch (e) {
      debugPrint('getScenarios error: $e');
      return null;
    }
  }

  Future<({Map<String, dynamic>? data, int statusCode})> generateScenario(
    String targetEntityId,
  ) async {
    if (_baseUrl.isEmpty) return (data: null, statusCode: 0);
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/v1/scenarios/generate'),
            headers: await _authHeaders(),
            body: jsonEncode({'target_entity_id': targetEntityId}),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 201 || res.statusCode == 200) {
        return (
          data: jsonDecode(res.body) as Map<String, dynamic>,
          statusCode: res.statusCode,
        );
      }
      return (data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('generateScenario error: $e');
      return (data: null, statusCode: 0);
    }
  }

  Future<({Map<String, dynamic>? data, int statusCode})> startScenario(
    String scenarioId,
  ) async {
    if (_baseUrl.isEmpty) return (data: null, statusCode: 0);
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/v1/scenarios/$scenarioId/start'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 || res.statusCode == 201) {
        return (
          data: jsonDecode(res.body) as Map<String, dynamic>,
          statusCode: res.statusCode,
        );
      }
      return (data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('startScenario error: $e');
      return (data: null, statusCode: 0);
    }
  }

  Future<int> dismissScenario(String scenarioId) async {
    if (_baseUrl.isEmpty) return 0;
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/v1/scenarios/$scenarioId/dismiss'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 15));
      return res.statusCode;
    } catch (e) {
      debugPrint('dismissScenario error: $e');
      return 0;
    }
  }

  // Fire-and-forget bulk confidence update for session_logs.confidence
  Future<int> setSessionConfidence({
    required String sessionId,
    required List<Map<String, dynamic>> items,
  }) async {
    if (_baseUrl.isEmpty || items.isEmpty) return 0;
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/v1/sessions/$sessionId/confidence'),
            headers: await _authHeaders(),
            body: jsonEncode({'confidence_by_turn': items}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        debugPrint('setSessionConfidence ${res.statusCode}: ${res.body}');
      }
      return res.statusCode;
    } catch (e) {
      debugPrint('setSessionConfidence error: $e');
      return 0;
    }
  }

}
