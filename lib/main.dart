import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:medsoft_patient/claim_qr.dart';
import 'package:medsoft_patient/constants.dart';
import 'package:medsoft_patient/guide.dart';
import 'package:medsoft_patient/login.dart';
import 'package:medsoft_patient/profile_screen.dart';
import 'package:medsoft_patient/qr_scan_screen.dart';
import 'package:medsoft_patient/webview_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uni_links/uni_links.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      title: 'Patient App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
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
                child: Text(
                  "Нэвтрэх төлөв шалгах үед алдаа гарлаа: ${snapshot.error}",
                ),
              ),
            );
          } else if (snapshot.hasData) {
            return snapshot.data!;
          } else {
            return const LoginScreen();
          }
        },
      ),
    );
  }

  Future<Widget> _getInitialScreen() async {
    final prefs = await SharedPreferences.getInstance();

    final initialLink = await getInitialLink();
    debugPrint("IN MY MAIN'S _getInitialScreen initialLink: $initialLink");

    if (initialLink != null) {
      Uri uri = Uri.parse(initialLink);

      if (uri.pathSegments.isNotEmpty &&
          uri.pathSegments[0] == 'qr' &&
          uri.pathSegments.length > 1) {
        String token = uri.pathSegments[1];
        await prefs.setString('scannedToken', token);
        debugPrint('Scanned token stored: $token');
      }
    }

    final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    debugPrint('isLoggedIn: $isLoggedIn');

    final String? xMedsoftToken = prefs.getString('X-Medsoft-Token');
    final bool isGotMedsoftToken =
        xMedsoftToken != null && xMedsoftToken.isNotEmpty;
    debugPrint('isGotMedsoftToken: $isGotMedsoftToken');

    final String? username = prefs.getString('Username');
    final bool isGotUsername = username != null && username.isNotEmpty;
    debugPrint('isGotUsername: $isGotUsername');

    if (isLoggedIn && isGotMedsoftToken && isGotUsername) {
      return const MyHomePage(title: 'Дуудлагын жагсаалт');
    } else {
      return const LoginScreen();
    }
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const platform = MethodChannel('com.example.medsoft_patient/location');

  String _liveLocation = "Fetching live location...";
  final List<String> _locationHistory = [];
  Map<String, dynamic> sharedPreferencesData = {};
  bool _isLoading = false;
  Map<String, dynamic>? roomInfo;
  String? _errorMessage;
  Widget _currentBody = Container();
  Timer? _timer;
  bool _isDialogShowing = false;

  @override
  void initState() {
    super.initState();

    Future<void> saveScannedToken(String token) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('scannedToken', token);
    }

    Future<String?> getSavedToken() async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('scannedToken');
    }

    Future<bool> callWaitApi(String token) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final tokenSaved = prefs.getString('X-Medsoft-Token') ?? '';
        final server = prefs.getString('X-Tenant') ?? '';

        final waitResponse = await http.get(
          Uri.parse('${Constants.appUrl}/qr/wait?id=$token'),
          headers: {"Authorization": "Bearer $tokenSaved"},
        );

        debugPrint('Main Wait API Response: ${waitResponse.body}');

        if (waitResponse.statusCode == 200) {
          return true;
        } else {
          return false;
        }
      } catch (e) {
        debugPrint('Error calling MAIN wait API: $e');
        return false;
      }
    }

    linkStream.listen((link) async {
      if (link != null) {
        Uri uri = Uri.parse(link);
        if (uri.pathSegments.isNotEmpty && uri.pathSegments[0] == 'qr') {
          String token = uri.pathSegments[1];
          debugPrint('Deep link token: $token');
          await saveScannedToken(token);

          bool waitSuccess = false;

          final prefs = await SharedPreferences.getInstance();
          if (prefs.getBool('isLoggedIn') == true) {
            waitSuccess = await callWaitApi(token);
          }

          if (waitSuccess && mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ClaimQRScreen(token: token)),
            );
          }
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('isLoggedIn') == true) {
        _initializeNotifications();
        _loadSharedPreferencesData();
        _sendXMedsoftTokenToAppDelegate();
        _currentBody = _buildLocationBody();
        platform.setMethodCallHandler(_methodCallHandler);
        WidgetsBinding.instance.addObserver(this);
        _startApiPolling();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopApiPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startApiPolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopApiPolling();
    }
  }

  void _startApiPolling() {
    _stopApiPolling();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) async {
      await _callApi();
    });

    _callApi();
  }

  void _stopApiPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _callApi() async {
    if (_isDialogShowing) {
      debugPrint("⏸ Skipping API call because dialog is showing.");
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('X-Medsoft-Token') ?? '';

      if (token.isEmpty) {
        debugPrint("⚠️ No token found, skipping API call.");
        return;
      }

      final response = await http.get(
        Uri.parse("${Constants.appUrl}/room/done_request"),
        headers: {"Authorization": "Bearer $token"},
      );

      debugPrint("✅ API response: ${response.statusCode} ${response.body}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonBody = json.decode(response.body);

        if (jsonBody['success'] == true &&
            jsonBody['data']?['doneRequested'] == true) {
          if (!_isDialogShowing) {
            _showDoneDialog();
          }
        }
      }
    } catch (e) {
      debugPrint("❌ API error: $e");
    }
  }

  void _showDoneDialog() {
    _isDialogShowing = true;
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            title: const Text("Үзлэг дууссан"),
            content: const Text("Үзсэн дууссан эсэхийг баталгаажуулна уу?"),
            actions: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () {
                  Navigator.of(context).pop();
                  _isDialogShowing = false;

                  debugPrint("❌ User declined the request.");
                },
                child: const Text("Татгалзах"),
              ),

              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.green),
                onPressed: () async {
                  Navigator.of(context).pop();
                  _isDialogShowing = false;

                  debugPrint("✅ User accepted the request.");

                  final prefs = await SharedPreferences.getInstance();
                  final token = prefs.getString('X-Medsoft-Token') ?? '';
                  final currentRoomId = prefs.getString('currentRoomId') ?? '';

                  if (token.isEmpty) {
                    debugPrint("⚠️ No token found, cannot call done API.");
                    return;
                  }

                  try {
                    if (currentRoomId.isEmpty) {
                      debugPrint("⚠️ No roomId found, cannot call done API.");
                      return;
                    }
                    debugPrint(
                      "currentRoomId: ${prefs.getString('currentRoomId')}",
                    );

                    debugPrint(
                      "URL: ${Uri.parse("${Constants.appUrl}/room/done")}",
                    );
                    final response = await http.post(
                      Uri.parse("${Constants.appUrl}/room/done"),
                      headers: {
                        'Authorization': 'Bearer $token',
                        'Content-Type': 'application/json',
                      },
                      body: json.encode({'roomId': currentRoomId}),
                    );

                    debugPrint(
                      "📡 Done API response: ${response.statusCode} ${response.body}",
                    );

                    if (response.statusCode == 200) {
                      debugPrint("✅ Done confirmed, stopping timer.");
                      _stopApiPolling();
                    } else {
                      debugPrint(
                        "❌ Done API failed with status: ${response.statusCode}",
                      );
                    }
                  } catch (e) {
                    debugPrint("❌ Done API error: $e");
                  }
                },
                child: const Text("Зөвшөөрөх"),
              ),
            ],
          ),
    );
  }

  Future<void> fetchRoom() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
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
          _logOut();
        }
        return;
      }

      final uri = Uri.parse('${Constants.appUrl}/room/get/patient');
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        debugPrint('API Response Body: ${response.body}');
        if (json['success'] == true) {
          roomInfo = json['data'];

          if (roomInfo is Map<String, dynamic> &&
              roomInfo!.containsKey('url') &&
              roomInfo!.containsKey('roomId')) {
            final url = roomInfo!['url'] as String;
            final title = "Байршил";
            final roomId = roomInfo!['roomId'] as String;

            await prefs.setString('currentRoomId', roomId);
            final roomIdNum = roomInfo!['_id'];

            debugPrint('roomIdNum: ' + roomIdNum);
            await platform.invokeMethod('sendRoomIdToAppDelegate', {
              'roomId': roomId,
            });

            await platform.invokeMethod('startLocationManagerAfterLogin');

            debugPrint("WebView loading URL: $url");
            debugPrint("WebView loading roomId: $roomId");
            debugPrint("WebView loading roomIdNum: $roomIdNum");

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

            setState(() {
              _isLoading = false;
              _errorMessage = null;
              _currentBody = _buildLocationBody();
            });
            debugPrint('Room fetch success! Navigating...');
          } else {
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
    final prefsMap = {for (var key in prefs.getKeys()) key: prefs.get(key)};
    debugPrint("prefs: $prefsMap");
    Map<String, dynamic> data = {};
    for (String key in prefs.getKeys()) {
      if (key == 'isLoggedIn' || key == 'arrivedInFifty') {
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

    await prefs.setBool('isLoggedIn', false);
    await prefs.remove('X-Tenant');
    await prefs.remove('X-Medsoft-Token');
    await prefs.remove('Username');
    await prefs.remove('scannedToken');
    await prefs.remove('tenantDomain');
    try {
      await platform.invokeMethod('stopLocationUpdates');
    } on PlatformException catch (e) {
      debugPrint("Failed to stop location updates: '${e.message}'.");
    }
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  Future<void> _showNotification() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'medsoft_channel_id',
          'Медсофт Мэдэгдэл',
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
                  'assets/icon/logoTransparent.png',
                  width: 150,
                  height: 150,
                ),
              ),
            ),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
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
                    leading: const Icon(
                      Icons.info_outline,
                      color: Colors.blueAccent,
                    ),
                    title: const Text(
                      'Хэрэглэх заавар',
                      style: TextStyle(fontSize: 18),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const GuideScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.location_on, color: Colors.teal),
                    title: const Text(
                      'Байршил',
                      style: TextStyle(fontSize: 18),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _currentBody = _buildLocationBody();
                      });
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.person, color: Colors.deepPurple),
                    title: const Text(
                      'Профайл',
                      style: TextStyle(fontSize: 18),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _currentBody = const ProfileScreen();
                      });
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.qr_code_scanner,
                      color: Colors.green,
                    ),
                    title: const Text(
                      'QR код унших',
                      style: TextStyle(fontSize: 18),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const QrScanScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

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
                onTap: () {
                  _logOut();
                },
              ),
            ),

            const SizedBox(height: 10),
          ],
        ),
      ),
      body: _currentBody,
    );
  }
}
