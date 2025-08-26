import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:medsoft_patient/guide.dart';
import 'package:medsoft_patient/login.dart';
import 'package:medsoft_patient/profile_screen.dart';
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
  Widget _currentBody = Container();

  @override
  void initState() {
    super.initState();
    _currentBody = _buildLocationBody();
    _initializeNotifications();
    platform.setMethodCallHandler(_methodCallHandler);

    _loadSharedPreferencesData();

    _sendXMedsoftTokenToAppDelegate();
  }

  Future<void> _checkInitialLoginState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    String? xServer = prefs.getString('X-Tenant');
    bool isGotToken = xServer != null && xServer.isNotEmpty;

    String? xMedsoftServer = prefs.getString('X-Medsoft-Token');
    bool isGotMedsoftToken =
        xMedsoftServer != null && xMedsoftServer.isNotEmpty;

    String? username = prefs.getString('Username');
    bool isGotUsername = username != null && username.isNotEmpty;

    debugPrint(
      'Login State: isLoggedIn=$isLoggedIn, isGotToken=$isGotToken, isGotMedsoftToken=$isGotMedsoftToken, isGotUsername=$isGotUsername',
    );

    if (!(isLoggedIn && isGotToken && isGotMedsoftToken && isGotUsername)) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  Future<void> fetchRoom() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('X-Medsoft-Token') ?? '';

    final uri = Uri.parse('https://app.medsoft.care/api/room/get/patient');

    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['success'] == true) {
        setState(() {
          roomInfo = json['data'];
          _isLoading = false;
        });

        final url = roomInfo['url'];
        final title = "Газрын зураг";
        final roomId = roomInfo['roomId'];
        final roomIdNum = roomInfo['_id'];

        await platform.invokeMethod('sendRoomIdToAppDelegate', {
          'roomId': roomId,
        });

        await platform.invokeMethod('startLocationManagerAfterLogin');

        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => WebViewScreen(
                  url: url,
                  title: title,
                  roomId: roomId,
                  roomIdNum: roomIdNum,
                ),
          ),
        );
      }
    } else {
      setState(() => _isLoading = false);
      debugPrint('Failed to fetch patients: ${response.statusCode}');
      if (response.statusCode == 401 || response.statusCode == 403) {
        _logOut();
      }
    }
  }

  void _logOut() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
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

  Widget _buildLocationBody() {
    return Center(
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00CCCC),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed:
            _isLoading
                ? null
                : () async {
                  setState(() => _isLoading = true);
                  await fetchRoom();
                },
        icon: const Icon(Icons.map),
        label: Text(
          _isLoading ? 'Түр хүлээнэ үү...' : 'Газрын зураг харах',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xFF00CCCC),
        title: const Text('Байршил тогтоогч'),
      ),
      drawer: Drawer(
        child: Column(
          children: <Widget>[
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Color.fromARGB(255, 236, 169, 175),
              ),
              child: Center(
                child: Image.asset(
                  'assets/icon/logo.png',
                  width: 150,
                  height: 150,
                ),
              ),
            ),
            ListTile(
              title: Center(
                child: Text(
                  sharedPreferencesData['Username'] ?? 'Guest',
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.blueAccent),
              title: const Text(
                'Хэрэглэх заавар',
                style: TextStyle(fontSize: 18),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const GuideScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on, color: Colors.teal),
              title: const Text('Байршил', style: TextStyle(fontSize: 18)),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _currentBody = _buildLocationBody();
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.person, color: Colors.deepPurple),
              title: const Text('Профайл', style: TextStyle(fontSize: 18)),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _currentBody = const ProfileScreen();
                });
              },
            ),

            const Spacer(),
            Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 217, 83, 96),
                borderRadius: BorderRadius.circular(20),
              ),
              child: ListTile(
                title: const Center(
                  child: Text(
                    'Гарах',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                onTap: _logOut,
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
      body: _currentBody,
    );
  }
}
