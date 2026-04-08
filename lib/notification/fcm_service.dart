import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'local_notification_service.dart';

String? globalFCMToken;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("🔔 Background message received: ${message.messageId}");

  final localNotifService = LocalNotificationService();

  final notification = message.notification;
  if (notification != null && notification.title != null && notification.body != null) {
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
      presentBadge: false,
    );
    final details = NotificationDetails(android: androidDetails, iOS: iOSDetails);

    await localNotifService.plugin.show(0, title, body, details);

    debugPrint('✅ Notification .show() called successfully');
  } else {
    debugPrint("⚠️ No notification content in message");
  }
}

class FCMService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final LocalNotificationService _localNotificationService = LocalNotificationService();

  Future<void> initFCM() async {
    await _localNotificationService.clearAppBadge();
    debugPrint("HERE------------------------------");

    await _localNotificationService.initializeNotifications();

    globalFCMToken = await _messaging.getToken();
    debugPrint("✅ FCM Token: $globalFCMToken");

    await _messaging.subscribeToTopic('all');
    await _messaging.unsubscribeFromTopic('all');
    debugPrint("📡 Subscribed and immediately Unsubscribed to topic 'all'");

    FirebaseMessaging.onMessage.listen(_firebaseMessagingForegroundHandler);

    FirebaseMessaging.onMessageOpenedApp.listen(_firebaseMessagingOnOpenAppHandler);
  }

  void _firebaseMessagingForegroundHandler(RemoteMessage message) {
    debugPrint('📬 Foreground message: ${message.notification?.title}');
    debugPrint("----------------- START OF FULL MESSAGE -----------------");
    debugPrint(jsonEncode(message.toMap()));
    debugPrint("------------------ END OF FULL MESSAGE ------------------");

    if (message.notification != null) {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'medsoft_channel_id',
        'Медсофт Мэдэгдэл',
        channelDescription: 'Системээс гарах болон бусад чухал мэдэгдлүүд',
        importance: Importance.max,
        priority: Priority.high,
      );

      const iOSDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: false,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iOSDetails,
      );

      debugPrint("🔔 FF Push noti TITLE: ${message.notification!.title}");
      debugPrint("🔔 FF Push noti BODY: ${message.notification!.body}");

      _localNotificationService.plugin.show(
        message.notification.hashCode,
        message.notification!.title,
        message.notification!.body,
        notificationDetails,
        payload: 'deep_link_data',
      );
    }
  }

  void _firebaseMessagingOnOpenAppHandler(RemoteMessage message) {
    debugPrint('➡️ Notification tapped, app opened/resumed: ${message.notification?.title}');
  }
}
