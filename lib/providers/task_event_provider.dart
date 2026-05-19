import 'package:flutter/material.dart';
import '../models/task_event_models.dart';
import '../services/task_event_service.dart';

class TaskEventProvider with ChangeNotifier {
  final TaskEventService _service = TaskEventService();

  List<EventItem> _events = [];
  List<AppNotification> _notifications = [];
  bool _isLoading = false;

  List<EventItem> get events => _events;
  List<AppNotification> get notifications => _notifications;
  bool get isLoading => _isLoading;

  Future<void> loadData(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _events = await _service.getEvents(userId);
      _notifications = await _service.getNotifications(userId);
    } catch (e) {
      print('Failed to load events and notifications: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addEvent(EventItem event) async {
    await _service.addEvent(event);
    _events.insert(0, event);
    notifyListeners();
  }

  Future<void> toggleEventCompleted(String eventId) async {
    final idx = _events.indexWhere((e) => e.id == eventId);
    if (idx == -1) return;
    final cur = _events[idx];
    final newVal = !cur.isCompleted;
    _events[idx] = EventItem(
      id: cur.id,
      userId: cur.userId,
      sessionId: cur.sessionId,
      title: cur.title,
      description: cur.description,
      dueText: cur.dueText,
      startTime: cur.startTime,
      endTime: cur.endTime,
      location: cur.location,
      isAllDay: cur.isAllDay,
      isCompleted: newVal,
      externalEventId: cur.externalEventId,
      syncProvider: cur.syncProvider,
      createdAt: cur.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    notifyListeners();
    try {
      await _service.setEventCompleted(eventId, newVal);
    } catch (_) {
      _events[idx] = cur;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteEvent(String eventId) async {
    final idx = _events.indexWhere((e) => e.id == eventId);
    if (idx == -1) return;
    final removed = _events.removeAt(idx);
    notifyListeners();
    try {
      await _service.deleteEvent(eventId);
    } catch (_) {
      _events.insert(idx, removed);
      notifyListeners();
      rethrow;
    }
  }
}
