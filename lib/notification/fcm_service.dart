import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Import the local notification service to display push notifications as local notifications
import 'local_notification_service.dart';

// Global variable for the FCM token
String? globalFCMToken;

// Instance of the local notification service, now using the factory constructor
// to get the singleton instance provided by local_notification_service.dart.
// final LocalNotificationService _localNotificationService = LocalNotificationService();

// Define iOS details for use in background handler
// const _iOSBackgroundDetails = DarwinNotificationDetails(
//   presentAlert: true, // CRITICAL: Forces the notification to be displayed
//   presentSound: true,
//   presentBadge: true,
// );

/// A handler for background messages (executed when the app is terminated or in the background).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("🔔 Background message received: ${message.messageId}");

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  const iOSInit = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
    defaultPresentAlert: true,
    defaultPresentSound: true,
    defaultPresentBadge: true,
  );
  const initSettings = InitializationSettings(iOS: iOSInit);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  final notification = message.notification;
  if (notification != null) {
    final title = notification.title ?? 'No title';
    final body = notification.body ?? 'No body';
    debugPrint("🔔 Background TITLE: $title");
    debugPrint("🔔 Background BODY: $body");

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'medsoft_channel_id',
      title,
      channelDescription: body,
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );

    const iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails);

    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      details,
      // payload: jsonEncode(message.data),
    );

    debugPrint('✅ Notification .show() called successfully');
  } else {
    debugPrint("⚠️ No notification content in message");
  }
}

class FCMService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  // Use the singleton instance
  final LocalNotificationService _localNotificationService = LocalNotificationService();

  // Remove the constructor parameter since we use the singleton instance directly
  // FCMService(this._localNotificationService);

  /// Initializes Firebase Messaging, requests permissions, gets the token, and sets up listeners.
  Future<void> initFCM() async {
    debugPrint("HERE------------------------------");
    // Initialize the local notification service first (must be called once)
    await _localNotificationService.initializeNotifications();

    // iOS permission
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    // Get device token
    globalFCMToken = await _messaging.getToken();
    debugPrint("✅ FCM Token: $globalFCMToken");

    // ✅ Subscribe to broadcast topic "all" (Unsubscribing from 'all' is strange,
    // keeping the original code's intent but noting it might be a mistake)
    await _messaging.subscribeToTopic('all');
    await _messaging.unsubscribeFromTopic('all');
    debugPrint("📡 Subscribed and immediately Unsubscribed to topic 'all'");

    // Foreground listener
    FirebaseMessaging.onMessage.listen(_firebaseMessagingForegroundHandler);

    // Handler for when a user taps a notification while the app is in the background/terminated
    FirebaseMessaging.onMessageOpenedApp.listen(_firebaseMessagingOnOpenAppHandler);
  }

  /// Handles incoming FCM messages when the app is in the foreground.
  void _firebaseMessagingForegroundHandler(RemoteMessage message) {
    debugPrint('📬 Foreground message: ${message.notification?.title}');

    // Use the local notification plugin to display the notification
    if (message.notification != null) {
      const iOSDetails = DarwinNotificationDetails(
        presentAlert: true, // <-- This MUST be present
        presentSound: true,
        presentBadge: true,
      );

      debugPrint("🔔 FF Background TITLE: ${message.notification!.title}");
      debugPrint("🔔 FF Background BODY: ${message.notification!.body}");

      _localNotificationService.plugin.show(
        message.notification.hashCode,
        message.notification!.title,
        message.notification!.body,
        const NotificationDetails(
          // ... android details
          // ✅ CRITICAL: Ensure you use the constant with presentation options
          iOS: iOSDetails, // Use the details that force presentation
        ),
        payload: 'deep_link_data',
      );
    }
  }

  /// Handles when a user taps an FCM notification and the app opens/resumes.
  void _firebaseMessagingOnOpenAppHandler(RemoteMessage message) {
    debugPrint('➡️ Notification tapped, app opened/resumed: ${message.notification?.title}');
    // You can use navigatorKey to navigate the user to a specific screen
    // navigatorKey.currentState?.pushNamed('/some_route');
  }
}
