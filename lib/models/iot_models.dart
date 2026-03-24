class IoTDevice {
  final String id;
  final String userId;
  final String deviceName;
  final String? deviceType;
  final String? room;
  final String? provider;
  final String? externalId;
  final Map<String, dynamic>? state;
  final bool isOnline;
  final DateTime lastSyncedAt;

  IoTDevice({
    required this.id,
    required this.userId,
    required this.deviceName,
    this.deviceType,
    this.room,
    this.provider,
    this.externalId,
    this.state,
    this.isOnline = true,
    required this.lastSyncedAt,
  });

  factory IoTDevice.fromJson(Map<String, dynamic> json) {
    return IoTDevice(
      id: json['id'],
      userId: json['user_id'],
      deviceName: json['device_name'],
      deviceType: json['device_type'],
      room: json['room'],
      provider: json['provider'],
      externalId: json['external_id'],
      state: json['state'],
      isOnline: json['is_online'] ?? true,
      lastSyncedAt: DateTime.parse(json['last_synced_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'device_name': deviceName,
      'device_type': deviceType,
      'room': room,
      'provider': provider,
      'external_id': externalId,
      'state': state,
      'is_online': isOnline,
      'last_synced_at': lastSyncedAt.toIso8601String(),
    };
  }
}
