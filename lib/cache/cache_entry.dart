class CacheEntry {
  final String key;
  final String? userId;        // null = global app entry
  final dynamic payload;       // Map or List
  final DateTime updatedAt;
  final int ttlSeconds;        // 0 = no expiry
  final int schemaVersion;
  final String? payloadHash;   // SHA-256 of serialized payload

  CacheEntry({
    required this.key,
    this.userId,
    required this.payload,
    required this.updatedAt,
    this.ttlSeconds = 0,
    this.schemaVersion = 1,
    this.payloadHash,
  });

  bool get isExpired {
    if (ttlSeconds == 0) return false;
    final expiry = updatedAt.add(Duration(seconds: ttlSeconds));
    return DateTime.now().isAfter(expiry);
  }

  int get ageMs => DateTime.now().difference(updatedAt).inMilliseconds;

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'user_id': userId,
      'payload': payload,
      'updated_at': updatedAt.toIso8601String(),
      'ttl_seconds': ttlSeconds,
      'schema_version': schemaVersion,
      'payload_hash': payloadHash,
    };
  }

  factory CacheEntry.fromMap(Map<String, dynamic> map) {
    return CacheEntry(
      key: map['key'],
      userId: map['user_id'],
      payload: map['payload'],
      updatedAt: DateTime.parse(map['updated_at']),
      ttlSeconds: map['ttl_seconds'] ?? 0,
      schemaVersion: map['schema_version'] ?? 1,
      payloadHash: map['payload_hash'],
    );
  }
}
