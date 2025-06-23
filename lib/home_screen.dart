import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:medsoft_patient/login.dart';
import 'package:medsoft_patient/webview_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const platform = MethodChannel('com.example.medsoft_patient/location');

  String _liveLocation = "Fetching live location...";
  final List<String> _locationHistory = [];
  Map<String, dynamic> sharedPreferencesData = {};
  bool _isLoading = false;
  dynamic roomInfo = {};

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    platform.setMethodCallHandler(_methodCallHandler);
    // _sendXTokenToAppDelegate();
    _loadSharedPreferencesData();
    // _sendXServerToAppDelegate();
    _sendXMedsoftTokenToAppDelegate();
    fetchRoom();
    _startLocationTracking();
  }

  Future<void> fetchRoom() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('X-Medsoft-Token') ?? '';
    // final server = prefs.getString('X-Server') ?? '';

    final uri = Uri.parse('https://app.medsoft.care/api/room/get/patient');

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        // 'X-Medsoft-Token': token,
        // 'X-Server': server,
        // 'X-Token': Constants.xToken,
      },
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['success'] == true) {
        setState(() {
          roomInfo = json['data'];
          _isLoading = false;
        });

        final url = roomInfo['url'];
        final title = "Patient Map";
        final roomId = roomInfo['roomId'];

        await platform.invokeMethod('sendRoomIdToAppDelegate', {
          'roomId': roomId,
        });

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WebViewScreen(url: url, title: title),
          ),
        );
      }
    } else {
      // Handle error
      setState(() => _isLoading = false);
      debugPrint('Failed to fetch patients: ${response.statusCode}');
    }
  }

  Future<void> _methodCallHandler(MethodCall call) async {
    if (call.method == 'updateLocation') {
      final locationData = call.arguments as Map;
      final latitude = locationData['latitude'];
      final longitude = locationData['longitude'];

      setState(() {
        _liveLocation =
            "Сүүлд илгээсэн байршил\nУртраг: $longitude\nӨргөрөг: $latitude";
        _addLocationToHistory(latitude, longitude);
      });
    } else if (call.method == 'navigateToLogin') {
      _logOut();
      _showNotification();
    }
  }

  void _addLocationToHistory(double latitude, double longitude) {
    String newLocation = "Уртраг: $longitude\nӨргөрөг: $latitude";

    if (_locationHistory.length >= 9) {
      _locationHistory.removeAt(0);
    }

    setState(() {
      _locationHistory.add(newLocation);
    });
  }

  Future<void> _loadSharedPreferencesData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> data = {};

    Set<String> allKeys = prefs.getKeys();
    for (String key in allKeys) {
      if (key == 'isLoggedIn') {
        data[key] = prefs.getBool(key);
      } else {
        data[key] = prefs.getString(key) ?? 'null';
      }
    }

    setState(() {
      sharedPreferencesData = data;
    });
  }

  void _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  // Future<void> _sendXTokenToAppDelegate() async {
  //   try {
  //     await platform.invokeMethod('sendXTokenToAppDelegate', {
  //       'xToken': Constants.xToken,
  //     });
  //   } on PlatformException catch (e) {
  //     debugPrint("Failed to send xToken to AppDelegate: '${e.message}'.");
  //   }
  // }

  // Future<void> _sendXServerToAppDelegate() async {
  //   SharedPreferences prefs = await SharedPreferences.getInstance();

  //   try {
  //     await platform.invokeMethod('sendXServerToAppDelegate', {
  //       'xServer': prefs.getString('X-Server'),
  //     });
  //   } on PlatformException catch (e) {
  //     debugPrint("Failed to send xToken to AppDelegate: '${e.message}'.");
  //   }
  // }

  Future<void> _sendXMedsoftTokenToAppDelegate() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    try {
      await platform.invokeMethod('sendXMedsoftTokenToAppDelegate', {
        'xMedsoftToken': prefs.getString('X-Medsoft-Token'),
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to send xToken to AppDelegate: '${e.message}'.");
    }
  }

  Future<void> _startLocationTracking() async {
    try {
      await platform.invokeMethod('startLocationManagerAfterLogin');
    } on PlatformException catch (e) {
      debugPrint("Error starting location manager: $e");
    }
  }

  void _logOut() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('X-Server');
    await prefs.remove('X-Medsoft-Token');
    await prefs.remove('Username');

    try {
      await platform.invokeMethod('stopLocationUpdates');
    } on PlatformException catch (e) {
      debugPrint("Failed to stop location updates: '${e.message}'.");
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  Future<void> _showNotification() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'your_channel_id',
          'your_channel_name',
          channelDescription: 'Your channel description',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: false,
        );

    const DarwinNotificationDetails iOSDetails = DarwinNotificationDetails(
      badgeNumber: 1,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      0,
      'Системээс гарсан байна.',
      'Ахин нэвтэрнэ үү.',
      notificationDetails,
      payload: 'item x',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Empty Screen')),
      body: const Center(child: Text('This is an empty screen')),
    );
  }
}
