import 'package:flutter/material.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService._internal();

  static final LocalNotificationService _instance = LocalNotificationService._internal();

  factory LocalNotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  FlutterLocalNotificationsPlugin get plugin => _flutterLocalNotificationsPlugin;

  static const String _channelId = 'medsoft_channel_id';
  static const String _channelName = 'Медсофт Мэдэгдэл';
  static const String _channelDescription = 'Системээс гарах болон бусад чухал мэдэгдлүүд';

  final AndroidNotificationChannel _androidChannel = const AndroidNotificationChannel(
    _channelId,
    _channelName,
    description: _channelDescription,
    importance: Importance.max,
  );

  bool _isInitialized = false;

  Future<void> initializeNotifications() async {
    if (_isInitialized) {
      debugPrint("🔔 Local notifications already initialized.");
      return;
    }

    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('app_icon');
    const DarwinInitializationSettings iOSSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iOSSettings,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification tapped: ${response.payload}');
      },
    );

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    _isInitialized = true;
    debugPrint("🔔 Local notifications initialized and Android channel created.");
  }

  Future<void> clearAppBadge() async {
    if (await FlutterAppBadger.isAppBadgeSupported()) {
      FlutterAppBadger.removeBadge();
      debugPrint("App badge cleared.");
    } else {
      debugPrint("App badge not supported on this device.");
    }
  }

  Future<void> showLogoutNotification() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );
    const DarwinNotificationDetails iOSDetails = DarwinNotificationDetails(badgeNumber: 0);

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      0,
      'Системээс гарсан байна.',
      'Ахин нэвтэрнэ үү.',
      notificationDetails,
    );
    debugPrint("🔔 Logout local notification shown.");
  }
}
