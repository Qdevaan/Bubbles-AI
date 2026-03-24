class Session {
  final String id;
  final String userId;
  final String? title;
  final String? summary;
  final String sessionType;
  final String mode;
  final bool isEphemeral;
  final bool isMultiplayer;
  final String persona;
  final String? deviceId;
  final DateTime startTime;
  final DateTime? endTime;
  final DateTime? endedAt;
  final String status;
  final bool isStarred;
  final double? sentimentScore;
  final int tokenUsagePrompt;
  final int tokenUsageCompletion;
  final double totalCostUsd;
  final DateTime? deletedAt;
  final DateTime createdAt;

  Session({
    required this.id,
    required this.userId,
    this.title,
    this.summary,
    this.sessionType = 'general',
    this.mode = 'general',
    this.isEphemeral = false,
    this.isMultiplayer = false,
    this.persona = 'casual',
    this.deviceId,
    required this.startTime,
    this.endTime,
    this.endedAt,
    this.status = 'active',
    this.isStarred = false,
    this.sentimentScore,
    this.tokenUsagePrompt = 0,
    this.tokenUsageCompletion = 0,
    this.totalCostUsd = 0.0,
    this.deletedAt,
    required this.createdAt,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'],
      userId: json['user_id'],
      title: json['title'],
      summary: json['summary'],
      sessionType: json['session_type'] ?? 'general',
      mode: json['mode'] ?? json['session_type'] ?? 'general',
      isEphemeral: json['is_ephemeral'] ?? false,
      isMultiplayer: json['is_multiplayer'] ?? false,
      persona: json['persona'] ?? 'casual',
      deviceId: json['device_id'],
      startTime: DateTime.parse(json['start_time']),
      endTime: json['end_time'] != null ? DateTime.parse(json['end_time']) : null,
      endedAt: json['ended_at'] != null ? DateTime.parse(json['ended_at']) : null,
      status: json['status'] ?? 'active',
      isStarred: json['is_starred'] ?? false,
      sentimentScore: json['sentiment_score']?.toDouble(),
      tokenUsagePrompt: json['token_usage_prompt'] ?? 0,
      tokenUsageCompletion: json['token_usage_completion'] ?? 0,
      totalCostUsd: (json['total_cost_usd'] ?? 0).toDouble(),
      deletedAt: json['deleted_at'] != null ? DateTime.parse(json['deleted_at']) : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'summary': summary,
      'session_type': sessionType,
      'mode': mode,
      'is_ephemeral': isEphemeral,
      'is_multiplayer': isMultiplayer,
      'persona': persona,
      'device_id': deviceId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'ended_at': endedAt?.toIso8601String() ?? endTime?.toIso8601String(),
      'status': status,
      'is_starred': isStarred,
      'sentiment_score': sentimentScore,
      'token_usage_prompt': tokenUsagePrompt,
      'token_usage_completion': tokenUsageCompletion,
      'total_cost_usd': totalCostUsd,
      'deleted_at': deletedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class SessionLog {
  final String id;
  final String sessionId;
  final int turnIndex;
  final String role;
  final String? speakerLabel;
  final String? content;
  final String? contentHtml;
  final double? sentimentScore;
  final String? sentimentLabel;
  final double? confidence;
  final String? modelUsed;
  final int? latencyMs;
  final int? tokensUsed;
  final String? finishReason;
  final bool hasError;
  final String? errorMessage;
  final DateTime createdAt;

  SessionLog({
    required this.id,
    required this.sessionId,
    required this.turnIndex,
    required this.role,
    this.speakerLabel,
    this.content,
    this.contentHtml,
    this.sentimentScore,
    this.sentimentLabel,
    this.confidence,
    this.modelUsed,
    this.latencyMs,
    this.tokensUsed,
    this.finishReason,
    this.hasError = false,
    this.errorMessage,
    required this.createdAt,
  });

  factory SessionLog.fromJson(Map<String, dynamic> json) => SessionLog(
        id: json['id'],
        sessionId: json['session_id'],
        turnIndex: json['turn_index'],
        role: json['role'],
        speakerLabel: json['speaker_label'],
        content: json['content'],
        contentHtml: json['content_html'],
        sentimentScore: json['sentiment_score']?.toDouble(),
        sentimentLabel: json['sentiment_label'],
        confidence: json['confidence']?.toDouble(),
        modelUsed: json['model_used'],
        latencyMs: json['latency_ms'],
        tokensUsed: json['tokens_used'],
        finishReason: json['finish_reason'],
        hasError: json['has_error'] ?? false,
        errorMessage: json['error_message'],
        createdAt: DateTime.parse(json['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'session_id': sessionId,
        'turn_index': turnIndex,
        'role': role,
        'speaker_label': speakerLabel,
        'content': content,
        'content_html': contentHtml,
        'sentiment_score': sentimentScore,
        'sentiment_label': sentimentLabel,
        'confidence': confidence,
        'model_used': modelUsed,
        'latency_ms': latencyMs,
        'tokens_used': tokensUsed,
        'finish_reason': finishReason,
        'has_error': hasError,
        'error_message': errorMessage,
        'created_at': createdAt.toIso8601String(),
      };
}
