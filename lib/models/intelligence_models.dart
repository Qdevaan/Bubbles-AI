class MemoryItem {
  final String id;
  final String userId;
  final String? sessionId;
  final String content;
  final String memoryType;
  final double importance;
  final double confidence;
  final String source;
  final bool isPinned;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime? lastAccessedAt;
  final DateTime? expiresAt;

  MemoryItem({
    required this.id,
    required this.userId,
    this.sessionId,
    required this.content,
    required this.memoryType,
    this.importance = 1.0,
    this.confidence = 1.0,
    this.source = 'inferred',
    this.isPinned = false,
    this.isArchived = false,
    required this.createdAt,
    this.lastAccessedAt,
    this.expiresAt,
  });

  factory MemoryItem.fromJson(Map<String, dynamic> json) {
    return MemoryItem(
      id: json['id'],
      userId: json['user_id'],
      sessionId: json['session_id'],
      content: json['content'],
      memoryType: json['memory_type'],
      importance: (json['importance'] ?? 1.0).toDouble(),
      confidence: (json['confidence'] ?? 1.0).toDouble(),
      source: json['source'] ?? 'inferred',
      isPinned: json['is_pinned'] ?? false,
      isArchived: json['is_archived'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      lastAccessedAt: json['last_accessed_at'] != null ? DateTime.parse(json['last_accessed_at']) : null,
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'session_id': sessionId,
      'content': content,
      'memory_type': memoryType,
      'importance': importance,
      'confidence': confidence,
      'source': source,
      'is_pinned': isPinned,
      'is_archived': isArchived,
      'created_at': createdAt.toIso8601String(),
      'last_accessed_at': lastAccessedAt?.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
    };
  }
}

class Entity {
  final String id;
  final String userId;
  final String canonicalName;
  final String displayName;
  final String entityType;
  final List<String> aliases;
  final String? description;
  final int mentionCount;
  final bool isArchived;
  final DateTime? lastSeenAt;
  final DateTime createdAt;

  Entity({
    required this.id,
    required this.userId,
    required this.canonicalName,
    required this.displayName,
    required this.entityType,
    this.aliases = const [],
    this.description,
    this.mentionCount = 0,
    this.isArchived = false,
    this.lastSeenAt,
    required this.createdAt,
  });

  factory Entity.fromJson(Map<String, dynamic> json) {
    return Entity(
      id: json['id'],
      userId: json['user_id'],
      canonicalName: json['canonical_name'],
      displayName: json['display_name'] ?? json['canonical_name'],
      entityType: json['entity_type'],
      aliases: List<String>.from(json['aliases'] ?? []),
      description: json['description'],
      mentionCount: json['mention_count'] ?? 0,
      isArchived: json['is_archived'] ?? false,
      lastSeenAt: json['last_seen_at'] != null ? DateTime.parse(json['last_seen_at']) : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'canonical_name': canonicalName,
      'display_name': displayName,
      'entity_type': entityType,
      'aliases': aliases,
      'description': description,
      'mention_count': mentionCount,
      'is_archived': isArchived,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
