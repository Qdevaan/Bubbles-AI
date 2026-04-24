import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  factory NotificationService() => instance;

  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  NotificationService._internal();

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
    );

    await _localNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification clicked with payload: ${response.payload}');
        // Handle navigation based on payload if needed
      },
    );

    _initialized = true;
  }

  Future<void> requestPermissions() async {
    if (!_initialized) await init();

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _localNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();

    final IOSFlutterLocalNotificationsPlugin? iosImplementation =
        _localNotificationsPlugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    await iosImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? notifType,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (notifType == 'alert' && !(prefs.getBool('push_events') ?? true)) return;
    if (notifType == 'system' && !(prefs.getBool('push_announcements') ?? true)) return;
    if (notifType == 'highlight' && !(prefs.getBool('push_highlights') ?? true)) return;

    if (!_initialized) await init();

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'bubbles_alerts',
      'Bubbles Alerts',
      channelDescription: 'Important alerts and notifications from Bubbles',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: DarwinNotificationDetails(),
    );

    await _localNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
      payload: payload,
    );
  }

  Future<void> scheduleEventAlert({
    required String eventId,
    required String title,
    required String description,
    required DateTime dueDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('push_events') ?? true)) return;

    if (!_initialized) await init();

    // Schedule 1 hour before the event
    final scheduledDate = dueDate.subtract(const Duration(hours: 1));

    if (scheduledDate.isBefore(DateTime.now())) {
      // Cannot schedule in the past
      return;
    }

    // Convert string ID to a numeric ID deterministically
    final id = eventId.hashCode;

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'bubbles_events',
      'Upcoming Events',
      channelDescription: 'Notifications for upcoming events and deadlines',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: DarwinNotificationDetails(),
    );

    try {
      await _localNotificationsPlugin.zonedSchedule(
        id: id,
        title: 'Upcoming: $title',
        body: description.isNotEmpty ? description : 'You have an event coming up in 1 hour.',
        scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
        notificationDetails: platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'event_$eventId',
      );
    } catch (e) {
      debugPrint('Failed to schedule event notification: $e');
    }
  }

  Future<void> cancelEventAlert(String eventId) async {
    if (!_initialized) return;
    await _localNotificationsPlugin.cancel(id: eventId.hashCode);
  }

  Future<void> cancelAllNotifications() async {
    if (!_initialized) return;
    await _localNotificationsPlugin.cancelAll();
  }
}
