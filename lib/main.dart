import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:medsoft_patient/guide.dart';
import 'package:medsoft_patient/login.dart';
import 'package:medsoft_patient/profile_screen.dart';
import 'package:medsoft_patient/webview_screen.dart'; // Make sure this import is correct
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Patient App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true, // Recommended for modern Flutter apps
      ),
      home: FutureBuilder<Widget>(
        future: _getInitialScreen(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Text("Error checking login status: ${snapshot.error}"),
              ),
            );
          } else if (snapshot.hasData) {
            return snapshot.data!;
          } else {
            // Fallback, though snapshot.hasData should cover success
            return const LoginScreen();
          }
        },
      ),
    );
  }

  Future<Widget> _getInitialScreen() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    debugPrint('isLoggedIn: $isLoggedIn');

    String? xMedsoftToken = prefs.getString(
      'X-Medsoft-Token',
    ); // Corrected variable name for clarity
    bool isGotMedsoftToken = xMedsoftToken != null && xMedsoftToken.isNotEmpty;
    debugPrint('isGotMedsoftToken: $isGotMedsoftToken');

    String? username = prefs.getString('Username');
    bool isGotUsername = username != null && username.isNotEmpty;
    debugPrint('isGotUsername: $isGotUsername');

    if (isLoggedIn && isGotMedsoftToken && isGotUsername) {
      return const MainHomeScreen();
    } else {
      return const LoginScreen();
    }
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const platform = MethodChannel(
    'com.example.medsoft_patient/location',
  ); // Ensure this matches your native setup

  String _liveLocation = "Fetching live location...";
  final List<String> _locationHistory = [];
  Map<String, dynamic> sharedPreferencesData = {};
  bool _isLoading = false;
  Map<String, dynamic>?
  roomInfo; // Explicitly make it nullable and Map<String, dynamic>
  String? _errorMessage; // State variable to hold error message
  Widget _currentBody = Container();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _loadSharedPreferencesData();
    _sendXMedsoftTokenToAppDelegate();
    _currentBody = _buildLocationBody(); // Initialize with the location body
    platform.setMethodCallHandler(_methodCallHandler);
    // _startLocationTracking();
  }

  Future<void> fetchRoom() async {
    setState(() {
      _isLoading = true;
      _errorMessage =
          null; // Clear any previous error messages when starting a new fetch
      _currentBody = _buildLocationBody();
    });

    debugPrint(
      'Fetching room... _isLoading: $_isLoading, _errorMessage: $_errorMessage',
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('X-Medsoft-Token') ?? '';
      if (token.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Алдаа: Нэвтрэх эрх байхгүй байна. Дахин нэвтэрнэ үү.';
          _currentBody = _buildLocationBody();
        });
        debugPrint('Error: Token is empty, setting error and logging out.');
        if (mounted) {
          // Ensure widget is still in tree before logging out
          _logOut(); // Force logout if token is missing
        }
        return;
      }

      final uri = Uri.parse('https://app.medsoft.care/api/room/get/patient');
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        debugPrint('API Response Body: ${response.body}');
        if (json['success'] == true) {
          roomInfo =
              json['data']; // Assign directly, setState will happen later

          // Critical check: Ensure roomInfo is a Map and contains expected keys
          if (roomInfo is Map<String, dynamic> &&
              roomInfo!.containsKey('url') &&
              roomInfo!.containsKey('roomId')) {
            final url = roomInfo!['url'] as String;
            final title = "Байршил";
            final roomId = roomInfo!['roomId'] as String;

            final roomIdNum = roomInfo!['_id'];

            debugPrint('roomIdNum: ' + roomIdNum);
            await platform.invokeMethod('sendRoomIdToAppDelegate', {
              'roomId': roomId,
            });

            await platform.invokeMethod('startLocationManagerAfterLogin');

            debugPrint("WebView loading URL: ${url}");
            debugPrint("WebView loading roomId: ${roomId}");
            debugPrint("WebView loading roomIdNum: ${roomIdNum}");

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
            // Now, set state for success after potential navigation
            setState(() {
              _isLoading = false;
              _errorMessage = null; // Clear error on success
              _currentBody = _buildLocationBody();
            });
            debugPrint('Room fetch success! Navigating...');
          } else {
            // Case: roomInfo is null or missing expected keys
            setState(() {
              _isLoading = false;
              _errorMessage =
                  'Алдаа: Серверээс ирсэн мэдээлэл дутуу байна (url эсвэл roomId байхгүй).';
              _currentBody = _buildLocationBody();
            });
            debugPrint(
              'Error: roomInfo is null or missing "url"/"roomId" keys after successful API call. roomInfo: $roomInfo',
            );
          }
        } else {
          // Case: API call was 200 OK, but 'success' is false
          setState(() {
            _isLoading = false;
            _errorMessage =
                json['message'] ??
                'Өрөөний мэдээлэл татахад алдаа гарлаа: Амжилтгүй хүсэлт.';
            _currentBody = _buildLocationBody();
          });
          debugPrint('API success false: ${json['message']}');
        }
      } else {
        // Case: HTTP status code is not 200
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Серверийн алдаа: ${response.statusCode}. Дахин оролдоно уу.';
          _currentBody = _buildLocationBody();
        });
        debugPrint(
          'Failed to fetch patients with status code: ${response.statusCode}. Body: ${response.body}',
        );
      }
    } catch (e) {
      // Case: Any other exception during the process (network issues, parsing errors)
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Учирсан алдаа: ${e.toString()}. Интернет холболтоо шалгана уу.';
        _currentBody = _buildLocationBody();
      });
      debugPrint('Exception during fetchRoom: $e');
    }
    debugPrint(
      'fetchRoom finished. _isLoading: $_isLoading, _errorMessage: $_errorMessage',
    );
  }

  Future<void> _methodCallHandler(MethodCall call) async {
    if (call.method == 'updateLocation') {
      final locationData = call.arguments as Map;
      final latitude = locationData['latitude'];
      final longitude = locationData['longitude'];
      setState(() {
        _liveLocation =
            "Сүүлд илгээсэн байршил\nУртраг: $longitude\nӨргөрөг: $latitude"; // Use $ for interpolation
        _addLocationToHistory(latitude, longitude);
      });
    } else if (call.method == 'navigateToLogin') {
      _logOut();
      _showNotification();
    }
  }

  void _addLocationToHistory(double latitude, double longitude) {
    String newLocation =
        "Уртраг: $longitude\nӨргөрөг: $latitude"; // Use $ for interpolation
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
    for (String key in prefs.getKeys()) {
      // Explicitly handle different types if you know them, otherwise getString is safest default
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
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('app_icon');
    const DarwinInitializationSettings iOSSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
    final InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iOSSettings,
    );
    await flutterLocalNotificationsPlugin.initialize(settings);
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

  void _logOut() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('X-Server'); // Assuming 'X-Server' is a key you use
    await prefs.remove('X-Medsoft-Token');
    await prefs.remove('Username');
    try {
      await platform.invokeMethod('stopLocationUpdates');
    } on PlatformException catch (e) {
      debugPrint("Failed to stop location updates: '${e.message}'.");
    }
    if (mounted) {
      // Check if the widget is still in the tree before navigating
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  Future<void> _showNotification() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'medsoft_channel_id', // Unique channel ID
          'Медсофт Мэдэгдэл', // Channel name
          channelDescription: 'Системээс гарах болон бусад чухал мэдэгдлүүд',
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
    );
  }

  Widget _buildLocationBody() {
    debugPrint(
      'Building Location Body. Current _errorMessage: $_errorMessage, _isLoading: $_isLoading',
    );

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Display error message if present
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 10.0,
              ),
              padding: const EdgeInsets.all(15.0),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1), // Light red background
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(color: Colors.red, width: 1.5),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 18, // Increased font size
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          // Loading indicator
          if (_isLoading) const CircularProgressIndicator(),
          // Button to fetch map
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00CCCC),
                foregroundColor: Colors.white, // Text color
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed:
                  _isLoading ? null : fetchRoom, // Disable button when loading
              icon: const Icon(Icons.map),
              label: Text(
                _isLoading ? 'Түр хүлээнэ үү...' : 'Газрын зураг харах',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF00CCCC),
        title: const Text('Байршил тогтоогч'),
        foregroundColor: Colors.white, // Make app bar text white
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
                  'assets/icon/logoTransparent.png', // Ensure this path is correct
                  width: 150,
                  height: 150,
                ),
              ),
            ),
            ListTile(
              title: Center(
                child: Text(
                  sharedPreferencesData['Username'] ?? 'Зочин',
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
