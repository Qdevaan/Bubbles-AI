import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'cache_entry.dart';

class PersistentCacheService {
  PersistentCacheService._internal();
  static final PersistentCacheService instance = PersistentCacheService._internal();

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'app_cache.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cache_entries (
            key            TEXT PRIMARY KEY,
            user_id        TEXT,
            payload_json   TEXT NOT NULL,
            updated_at     INTEGER NOT NULL,
            ttl_seconds    INTEGER NOT NULL DEFAULT 0,
            schema_version INTEGER NOT NULL DEFAULT 1,
            payload_hash   TEXT
          )
        ''');
        await db.execute('CREATE INDEX idx_user_key ON cache_entries (user_id, key)');
        await db.execute('CREATE INDEX idx_updated_at ON cache_entries (updated_at)');
      },
    );

    await purgeExpired();
  }

  Future<CacheEntry?> read(String key) async {
    final db = _db;
    if (db == null) return null;

    final List<Map<String, dynamic>> maps = await db.query(
      'cache_entries',
      where: 'key = ?',
      whereArgs: [key],
    );

    if (maps.isEmpty) return null;

    final map = maps.first;
    final entry = CacheEntry(
      key: map['key'],
      userId: map['user_id'],
      payload: jsonDecode(map['payload_json']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at']),
      ttlSeconds: map['ttl_seconds'],
      schemaVersion: map['schema_version'],
      payloadHash: map['payload_hash'],
    );

    if (entry.isExpired) {
      await delete(key);
      return null;
    }

    return entry;
  }

  Future<void> write(CacheEntry entry) async {
    final db = _db;
    if (db == null) return;

    await db.insert(
      'cache_entries',
      {
        'key': entry.key,
        'user_id': entry.userId,
        'payload_json': jsonEncode(entry.payload),
        'updated_at': entry.updatedAt.millisecondsSinceEpoch,
        'ttl_seconds': entry.ttlSeconds,
        'schema_version': entry.schemaVersion,
        'payload_hash': entry.payloadHash,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String key) async {
    final db = _db;
    if (db == null) return;
    await db.delete('cache_entries', where: 'key = ?', whereArgs: [key]);
  }

  Future<void> purgeUserScope(String userId) async {
    final db = _db;
    if (db == null) return;
    await db.delete('cache_entries', where: 'user_id = ?', whereArgs: [userId]);
  }

  Future<void> purgeExpired() async {
    final db = _db;
    if (db == null) return;

    // We can't easily do a single SQL delete for all TTLs because they vary per row.
    // But we can delete where updatedAt + ttlSeconds < now.
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.delete(
      'cache_entries',
      where: 'ttl_seconds > 0 AND (updated_at + (ttl_seconds * 1000)) < ?',
      whereArgs: [now],
    );
  }

  Future<void> invalidateSchemaVersion(int version, String keyPrefix) async {
    final db = _db;
    if (db == null) return;
    await db.delete(
      'cache_entries',
      where: 'schema_version < ? AND key LIKE ?',
      whereArgs: [version, '$keyPrefix%'],
    );
  }

  Future<void> purgeAll() async {
    final db = _db;
    if (db == null) return;
    await db.delete('cache_entries');
  }
}

// Add a mixin for naming consistency in the CacheEntry constructor if I made a typo.
// I used payloadHash in CacheEntry, but payload_hash in the query result.
// Let's check CacheEntry.
