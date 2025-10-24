import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:medsoft_patient/api/auth_dao.dart';
import 'package:medsoft_patient/api/map_dao.dart';
import 'package:medsoft_patient/claim_qr.dart';
import 'package:medsoft_patient/guide.dart';
import 'package:medsoft_patient/history_screen.dart';
import 'package:medsoft_patient/login.dart';
import 'package:medsoft_patient/notification/fcm_service.dart';
import 'package:medsoft_patient/notification/local_notification_service.dart';
import 'package:medsoft_patient/notification_screen.dart';
import 'package:medsoft_patient/profile_screen.dart';
import 'package:medsoft_patient/qr_scan_screen.dart';
import 'package:medsoft_patient/time_order/time_order_screen.dart';
import 'package:medsoft_patient/webview_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uni_links/uni_links.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
// String? globalFCMToken;
// Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
//   await Firebase.initializeApp();
//   debugPrint("🔔 Background message: ${message.messageId}");
// }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Use the moved background handler from fcm_token.dart (not fcm_service.dart)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // --- NEW FCM INITIALIZATION LOGIC ---
  final fcmService = FCMService();
  await fcmService.initFCM(); // This calls _localNotificationService.initializeNotifications() and sets globalFCMToken
  // --- END NEW FCM INITIALIZATION LOGIC ---

  // Since globalFCMToken is now set, we can rely on it being available
  // when MyApp builds its initial screen.

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        // Add specific delegate for Mongolian if available, 
        // but flutter_localizations should handle 'mn' for date/time.
      ],
      
      // 2. DEFINE SUPPORTED LOCALES
      supportedLocales: const [
        Locale('en', ''), // English
        Locale('mn', ''), // Mongolian (mn) <-- REQUIRED
      ],
      
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
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          } else if (snapshot.hasError) {
            return Scaffold(
              body: Center(child: Text("Нэвтрэх төлөв шалгах үед алдаа гарлаа: ${snapshot.error}")),
            );
          } else if (snapshot.hasData) {
            return snapshot.data!;
          } else {
            debugPrint('globalFCMToken in MyApp build: $globalFCMToken');
            return LoginScreen(fcmToken: globalFCMToken);
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
    final bool isGotMedsoftToken = xMedsoftToken != null && xMedsoftToken.isNotEmpty;
    debugPrint('isGotMedsoftToken: $isGotMedsoftToken');

    final String? username = prefs.getString('Username');
    final bool isGotUsername = username != null && username.isNotEmpty;
    debugPrint('isGotUsername: $isGotUsername');

    if (isLoggedIn && isGotMedsoftToken && isGotUsername) {
      return const MyHomePage(title: 'Дуудлагын жагсаалт');
    } else {
      debugPrint('globalFCMToken in _getInitialScreen: $globalFCMToken');
      return LoginScreen(fcmToken: globalFCMToken);
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
  final LocalNotificationService _localNotificationService = LocalNotificationService();
  late final FCMService _fcmService;

  static const platform = MethodChannel('com.example.medsoft_patient/location');

  final _authDao = AuthDAO();
  final _mapDao = MapDAO();
  // String? _fcmToken;

  int _selectedIndex = 0;

  final List<String> _locationHistory = [];
  Map<String, dynamic> sharedPreferencesData = {};
  bool _isLoading = false;
  Map<String, dynamic>? roomInfo;
  String? _errorMessage;
  Timer? _timer;
  final bool _isDialogShowing = false;
  String appBarCaption = 'Медсофт';

  @override
  void initState() {
    super.initState();
    _fcmService = FCMService();
    _initServices();

    // _initFCM();
    Future<void> saveScannedToken(String token) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('scannedToken', token);
    }

    Future<bool> callWaitApi(String token) async {
      try {
        final apiResponse = await _authDao.claimQR(token);

        if (apiResponse.statusCode == 200) {
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
            Navigator.push(context, MaterialPageRoute(builder: (_) => ClaimQRScreen(token: token)));
          }
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('isLoggedIn') == true) {
        // _initializeNotifications();
        _loadSharedPreferencesData();
        _sendXMedsoftTokenToAppDelegate();
        platform.setMethodCallHandler(_methodCallHandler);
        WidgetsBinding.instance.addObserver(this);
        _startApiPolling();
      }
    });
  }

  Future<void> _initServices() async {
    // Initialize both FCM and Local Notifications
    await _localNotificationService.initializeNotifications();
    await _fcmService.initFCM();
  }
  // Future<void> _initFCM() async {
  //   debugPrint("HERE------------------------------");
  //   FirebaseMessaging messaging = FirebaseMessaging.instance;

  //   // iOS permission
  //   await messaging.requestPermission(alert: true, badge: true, sound: true);

  //   // Get device token
  //   // String? token = await messaging.getToken();
  //   globalFCMToken = await messaging.getToken();
  //   debugPrint("✅ FCM Token: $globalFCMToken");

  //   // ✅ Subscribe to broadcast topic "all"
  //   await messaging.subscribeToTopic('all');
  //   await messaging.unsubscribeFromTopic('all');
  //   debugPrint("📡 Subscribed to topic 'all'");

  //   // Foreground listener
  //   FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  //     debugPrint('📬 Foreground message: ${message.notification?.title}');
  //   });
  // }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopApiPolling();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      switch (index) {
        case 0:
          appBarCaption = 'Медсофт';
          break;
        case 1:
          appBarCaption = 'Цаг захиалга';
          break;
        case 2:
          appBarCaption = 'QR сканнер';
          break;
        case 3:
          appBarCaption = 'Өвчний түүх';
          break;
        case 4:
          appBarCaption = 'Профайл';
          break;
      }
    });
  }

  Widget _buildSelectedBody() {
    switch (_selectedIndex) {
      case 0:
        return _buildLocationBody();
      case 1:
        return const TimeOrderScreen();
      case 2:
        return const QrScanScreen();
      case 3:
        return const HistoryScreen();
      case 4:
        return const ProfileScreen();
      default:
        return _buildLocationBody();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startApiPolling();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _stopApiPolling();
    }
  }

  void _startApiPolling() {
    _stopApiPolling();
    _timer = Timer.periodic(const Duration(minutes: 60), (_) async {
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

      final response = await _mapDao.checkDoneRequest();

      debugPrint("✅ API response: ${response.statusCode} ${response.data}");

      if (response.statusCode == 200) {
        if (response.data!['success'] == true && response.data!['data']?['doneRequested'] == true) {
          if (!_isDialogShowing) {}
        }
      }
    } catch (e) {
      debugPrint("❌ API error: $e");
    }
  }

  Future<void> fetchRoom() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    debugPrint('Fetching room... _isLoading: $_isLoading, _errorMessage: $_errorMessage');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('X-Medsoft-Token') ?? '';
      if (token.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Алдаа: Нэвтрэх эрх байхгүй байна. Дахин нэвтэрнэ үү.';
        });
        debugPrint('Error: Token is empty, setting error and logging out.');
        if (mounted) {
          _logOut();
        }
        return;
      }

      final response = await _mapDao.getRoomInfo();

      if (response.statusCode == 200) {
        debugPrint('API Response data: ${response.data}');
        if (response.statusCode == 200 && response.data!['success'] == true) {
          roomInfo = response.data;

          if (roomInfo is Map<String, dynamic> &&
              roomInfo!.containsKey('url') &&
              roomInfo!.containsKey('roomId')) {
            final url = roomInfo!['url'] as String;
            final title = "Байршил";
            final roomId = roomInfo!['roomId'] as String;

            await prefs.setString('currentRoomId', roomId);
            final roomIdNum = roomInfo!['_id'];

            debugPrint('roomIdNum: ${roomIdNum.toString()}');
            await platform.invokeMethod('sendRoomIdToAppDelegate', {'roomId': roomId});

            await platform.invokeMethod('startLocationManagerAfterLogin');

            debugPrint("WebView loading URL: $url");
            debugPrint("WebView loading roomId: $roomId");
            debugPrint("WebView loading roomIdNum: $roomIdNum");

            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (context) =>
                        WebViewScreen(url: url, title: title, roomId: roomId, roomIdNum: roomIdNum),
              ),
            );

            setState(() {
              _isLoading = false;
              _errorMessage = null;
            });
            debugPrint('Room fetch success! Navigating...');
          } else {
            setState(() {
              _isLoading = false;
              _errorMessage =
                  'Алдаа: Серверээс ирсэн мэдээлэл дутуу байна (url эсвэл roomId байхгүй).';
            });
            debugPrint(
              'Error: roomInfo is null or missing "url"/"roomId" keys after successful API call. roomInfo: $roomInfo',
            );
          }
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage =
                response.data!['message'] ??
                'Өрөөний мэдээлэл татахад алдаа гарлаа: Амжилтгүй хүсэлт.';
          });
          debugPrint('API success false: ${response.data!['message']}');
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Серверийн алдаа: ${response.statusCode}. Дахин оролдоно уу.';
        });
        debugPrint(
          'Failed to fetch patients with status code: ${response.statusCode}. Body: ${response.data}',
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Учирсан алдаа: ${e.toString()}. Интернет холболтоо шалгана уу.';
      });
      debugPrint('Exception during fetchRoom: $e');
    }
    debugPrint('fetchRoom finished. _isLoading: $_isLoading, _errorMessage: $_errorMessage');
  }

  Future<void> _methodCallHandler(MethodCall call) async {
    if (call.method == 'updateLocation') {
      final locationData = call.arguments as Map;
      final latitude = locationData['latitude'];
      final longitude = locationData['longitude'];
      setState(() {
        _addLocationToHistory(latitude, longitude);
      });
    } else if (call.method == 'navigateToLogin') {
      _logOut();
      _localNotificationService.showLogoutNotification();
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

  // void _initializeNotifications() async {
  //   const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('app_icon');
  //   const DarwinInitializationSettings iOSSettings = DarwinInitializationSettings(
  //     requestAlertPermission: true,
  //     requestBadgePermission: true,
  //     requestSoundPermission: true,
  //   );
  //   final InitializationSettings settings = InitializationSettings(
  //     android: androidSettings,
  //     iOS: iOSSettings,
  //   );
  //   await flutterLocalNotificationsPlugin.initialize(settings);
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
      debugPrint('globalFCMToken at logout: $globalFCMToken');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen(fcmToken: globalFCMToken)),
      );
    }
  }

  // Future<void> _showNotification() async {
  //   const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
  //     'medsoft_channel_id',
  //     'Медсофт Мэдэгдэл',
  //     channelDescription: 'Системээс гарах болон бусад чухал мэдэгдлүүд',
  //     importance: Importance.max,
  //     priority: Priority.high,
  //     showWhen: false,
  //   );
  //   const DarwinNotificationDetails iOSDetails = DarwinNotificationDetails(badgeNumber: 1);
  //   const NotificationDetails notificationDetails = NotificationDetails(
  //     android: androidDetails,
  //     iOS: iOSDetails,
  //   );
  //   await flutterLocalNotificationsPlugin.show(
  //     0,
  //     'Системээс гарсан байна.',
  //     'Ахин нэвтэрнэ үү.',
  //     notificationDetails,
  //   );
  // }

  Widget _buildLocationBody() {
    return Center(
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00CCCC),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        leading: Padding(
          padding: const EdgeInsets.only(left: 15.0),
          child: Builder(
            builder:
                (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () {
                    Scaffold.of(context).openDrawer();
                  },
                ),
          ),
        ),
        backgroundColor: const Color(0xFF00CCCC),
        title: Text(appBarCaption),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 15.0),
            child: IconButton(
              icon: const Icon(Icons.notifications),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationScreen()),
                );
              },
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: _buildSelectedBody(),

      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: const Color(0xFF00CCCC),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Нүүр'),
          BottomNavigationBarItem(icon: Icon(Icons.schedule), label: 'Цаг авах'),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'QR'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Түүх'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Профайл'),
        ],
      ),
    );
  }

  Drawer _buildDrawer() {
    return Drawer(
      child: Column(
        children: <Widget>[
          DrawerHeader(
            decoration: const BoxDecoration(color: Color.fromARGB(255, 236, 169, 175)),
            child: Center(
              child: Image.asset('assets/icon/logoTransparent.png', width: 150, height: 150),
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
                  leading: const Icon(Icons.info_outline, color: Colors.blueAccent),
                  title: const Text('Хэрэглэх заавар', style: TextStyle(fontSize: 18)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const GuideScreen()),
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
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
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
    );
  }
}
