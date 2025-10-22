import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  // --- 1. SINGLETON PATTERN ---
  // Private constructor
  LocalNotificationService._internal();

  // Singleton instance
  static final LocalNotificationService _instance = LocalNotificationService._internal();

  // Factory constructor to return the singleton instance
  factory LocalNotificationService() => _instance;
  // --------------------------

  // Internal plugin instance
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  FlutterLocalNotificationsPlugin get plugin => _flutterLocalNotificationsPlugin;

  // --- 2. ANDROID CHANNEL SETUP (Critical for Android 8+) ---
  static const String _channelId = 'medsoft_channel_id';
  static const String _channelName = 'Медсофт Мэдэгдэл';
  static const String _channelDescription = 'Системээс гарах болон бусад чухал мэдэгдлүүд';

  final AndroidNotificationChannel _androidChannel = const AndroidNotificationChannel(
    _channelId,
    _channelName,
    description: _channelDescription,
    importance: Importance.max,
  );
  // --------------------------

  bool _isInitialized = false;

  /// Initializes the local notification settings for Android and iOS, and creates the Android channel.
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

    // Initialize plugin with settings and callback for notification taps
    await _flutterLocalNotificationsPlugin.initialize(settings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
      debugPrint('Notification tapped: ${response.payload}');
    });

    // CRITICAL: Create Android Notification Channel
    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
    
    _isInitialized = true;
    debugPrint("🔔 Local notifications initialized and Android channel created.");
  }

  /// Shows a notification specific to the logout use case.
  Future<void> showLogoutNotification() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId, // Use the defined channel ID
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );
    const DarwinNotificationDetails iOSDetails = DarwinNotificationDetails(badgeNumber: 1);
    
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      0, // Using ID 0 for a specific system alert like logout
      'Системээс гарсан байна.',
      'Ахин нэвтэрнэ үү.',
      notificationDetails,
    );
    debugPrint("🔔 Logout local notification shown.");
  }
}
