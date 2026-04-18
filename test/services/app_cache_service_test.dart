import 'package:flutter_test/flutter_test.dart';
import 'package:bubbles/services/app_cache_service.dart';

void main() {
  group('AppCacheService', () {
    late AppCacheService sut;

    setUp(() {
      sut = AppCacheService();
    });

    test('starts with all nulls', () {
      expect(sut.entities, isNull);
      expect(sut.events, isNull);
      expect(sut.highlights, isNull);
      expect(sut.notifications, isNull);
      expect(sut.cacheUserId, isNull);
    });

    test('setEntities stores data and userId', () {
      final data = [{'id': '1', 'name': 'Alice'}];
      sut.setEntities(data, 'user-123');
      expect(sut.entities, equals(data));
      expect(sut.cacheUserId, equals('user-123'));
    });

    test('setEntities makes a copy — original list mutation does not affect cache', () {
      final data = [{'id': '1'}];
      sut.setEntities(data, 'user-123');
      data.add({'id': '2'});
      expect(sut.entities!.length, equals(1));
    });

    test('setInsights stores all three lists', () {
      sut.setInsights(
        events: [{'id': 'e1'}],
        highlights: [{'id': 'h1'}],
        notifications: [{'id': 'n1'}],
        userId: 'user-abc',
      );
      expect(sut.events!.length, equals(1));
      expect(sut.highlights!.length, equals(1));
      expect(sut.notifications!.length, equals(1));
      expect(sut.cacheUserId, equals('user-abc'));
    });

    test('invalidateEntities nulls only entities', () {
      sut.setEntities([{'id': '1'}], 'u1');
      sut.setInsights(events: [{'id': 'e'}], highlights: [], notifications: [], userId: 'u1');
      sut.invalidateEntities();
      expect(sut.entities, isNull);
      expect(sut.events, isNotNull);
    });

    test('invalidateInsights nulls only insight lists', () {
      sut.setEntities([{'id': '1'}], 'u1');
      sut.setInsights(events: [{'id': 'e'}], highlights: [], notifications: [], userId: 'u1');
      sut.invalidateInsights();
      expect(sut.events, isNull);
      expect(sut.highlights, isNull);
      expect(sut.notifications, isNull);
      expect(sut.entities, isNotNull);
    });

    test('invalidateAll nulls everything including cacheUserId', () {
      sut.setEntities([{'id': '1'}], 'u1');
      sut.setInsights(events: [{'id': 'e'}], highlights: [], notifications: [], userId: 'u1');
      sut.invalidateAll();
      expect(sut.entities, isNull);
      expect(sut.events, isNull);
      expect(sut.highlights, isNull);
      expect(sut.notifications, isNull);
      expect(sut.cacheUserId, isNull);
    });

    test('notifyListeners fires on invalidateAll', () {
      var notified = false;
      sut.addListener(() => notified = true);
      sut.invalidateAll();
      expect(notified, isTrue);
    });
  });
}
