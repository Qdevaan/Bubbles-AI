class EventItem {
  final String id;
  final String userId;
  final String? sessionId;
  final String title;
  final String? description;
  final String? dueText;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? location;
  final bool isAllDay;
  final bool isCompleted;
  final String? externalEventId;
  final String? syncProvider;
  final DateTime createdAt;
  final DateTime updatedAt;

  EventItem({
    required this.id,
    required this.userId,
    this.sessionId,
    required this.title,
    this.description,
    this.dueText,
    this.startTime,
    this.endTime,
    this.location,
    this.isAllDay = false,
    this.isCompleted = false,
    this.externalEventId,
    this.syncProvider,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EventItem.fromJson(Map<String, dynamic> json) {
    return EventItem(
      id: json['id'],
      userId: json['user_id'],
      sessionId: json['session_id'],
      title: json['title'],
      description: json['description'],
      dueText: json['due_text'],
      startTime: json['start_time'] != null ? DateTime.parse(json['start_time']) : null,
      endTime: json['end_time'] != null ? DateTime.parse(json['end_time']) : null,
      location: json['location'],
      isAllDay: json['is_all_day'] ?? false,
      isCompleted: json['is_completed'] ?? false,
      externalEventId: json['external_event_id'],
      syncProvider: json['sync_provider'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'session_id': sessionId,
      'title': title,
      'description': description,
      'due_text': dueText,
      'start_time': startTime?.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'location': location,
      'is_all_day': isAllDay,
      'is_completed': isCompleted,
      'external_event_id': externalEventId,
      'sync_provider': syncProvider,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class AppNotification {
  final String id;
  final String userId;
  final String title;
  final String? body;
  final String? notifType;
  final String? actionUrl;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    this.body,
    this.notifType,
    this.actionUrl,
    this.isRead = false,
    this.readAt,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'],
      userId: json['user_id'],
      title: json['title'],
      body: json['body'],
      notifType: json['notif_type'],
      actionUrl: json['action_url'],
      isRead: json['is_read'] ?? false,
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at']) : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'body': body,
      'notif_type': notifType,
      'action_url': actionUrl,
      'is_read': isRead,
      'read_at': readAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
