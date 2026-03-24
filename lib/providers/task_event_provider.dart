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
}
