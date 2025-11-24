import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:medsoft_patient/api/auth_dao.dart';
import 'package:medsoft_patient/api/home_dao.dart';
import 'package:medsoft_patient/api/map_dao.dart';
import 'package:medsoft_patient/claim_qr.dart';
import 'package:medsoft_patient/constants.dart';
import 'package:medsoft_patient/guide.dart';
import 'package:medsoft_patient/history_screen.dart';
import 'package:medsoft_patient/login.dart';
import 'package:medsoft_patient/news.dart';
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
  // final fcmService = FCMService();
  // await fcmService
  //     .initFCM(); // This calls _localNotificationService.initializeNotifications() and sets globalFCMToken
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
  final _homeDao = HomeDAO();
  // String? _fcmToken;

  int _selectedIndex = 0;
  String? _historyKeyFromHome;

  final List<String> _locationHistory = [];
  Map<String, dynamic> sharedPreferencesData = {};
  bool _isLoading = false;
  Map<String, dynamic>? roomInfo;
  String? _errorMessage;
  Timer? _timer;
  bool _isDialogShowing = false;
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
      if (index != 3) {
        _historyKeyFromHome = null;
      }

      switch (index) {
        case 0:
          appBarCaption = 'Медсофт';
          break;
        case 1:
          appBarCaption = 'Цаг захиалга';
          break;
        case 2:
          appBarCaption = 'QR код уншигч';
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
        return HistoryScreen(initialHistoryKey: _historyKeyFromHome);
      case 4:
        return ProfileScreen(onGuideTap: _navigateToGuideScreen, onLogoutTap: _logOut);
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
                    debugPrint("currentRoomId: ${prefs.getString('currentRoomId')}");

                    debugPrint("URL: ${Uri.parse("${Constants.appUrl}/room/done")}");
                    // final response = await http.post(
                    //   Uri.parse("${Constants.appUrl}/room/done"),
                    //   headers: {
                    //     'Authorization': 'Bearer $token',
                    //     'Content-Type': 'application/json',
                    //   },
                    //   body: json.encode({'roomId': currentRoomId}),
                    // );

                    final response = await _mapDao.acceptDoneRequest({'roomId': currentRoomId});

                    debugPrint("📡 Done API response: ${response.statusCode}");

                    if (response.statusCode == 200) {
                      debugPrint("✅ Done confirmed, stopping timer.");
                      _stopApiPolling();
                    } else {
                      debugPrint("❌ Done API failed with status: ${response.statusCode}");
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
        // 🚨 ЗААВАР 1: API хариуны 'success' талбарыг зөв шалгах
        if (response.data is Map<String, dynamic> && response.success == true) {
          roomInfo = response.data;

          if (roomInfo is Map<String, dynamic> &&
              roomInfo!.containsKey('url') &&
              roomInfo!.containsKey('roomId')) {
            final url = roomInfo!['url'] as String;
            final title = "Байршил";
            final roomId = roomInfo!['roomId'] as String;
            final tenantName = roomInfo!['serverName'] as String;

            await prefs.setString('currentRoomId', roomId);
            await prefs.setString('xTenant', tenantName);
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
              _errorMessage = null; // Clear error on success
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
          // 🚨 ЗААВАР 1: API хариуны 'message' талбарыг зөв авах
          setState(() {
            _isLoading = false;
            // 'data' нь null биш гэж үзвэл data!['message']-г ашиглана
            _errorMessage = response.message ?? 'Алдаа: Мэдээлэл авах боломжгүй байна.';
          });
          debugPrint('API success false: ${response.message}');
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

    // 🚨 ЗААВАР 2: SnackBar логикийг тааруулж өөрчлөх
    if (_errorMessage != null && mounted) {
      // API-ийн жишээ хариу дахь мессежтэй тааруулсан
      final isCallError = _errorMessage! == 'Дуудлага байхгүй';

      // 'Дуудлага байхгүй' бол хар дэвсгэр, цагаан текст болгосон.
      final backgroundColor = isCallError ? Colors.black : Colors.red;

      // Текст бүх тохиолдолд цагаан
      final textColor = Colors.white;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: backgroundColor,
          content: Text(_errorMessage!, style: TextStyle(color: textColor)),
        ),
      );
    }
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

  void _navigateToGuideScreen() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const GuideScreen()));
  }

  void _logOut() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    prefs.clear();
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
    return Column(
      children: [
        // Top Half: NewsFeedWidget
        const Expanded(
          flex: 4, // Represents 40%
          child: NewsFeedWidget(),
        ),
        // 🎯 ШИНЭ ГАРЧИГ ХЭСЭГ: "Үйлчилгээ"
        Padding(
          padding: const EdgeInsets.only(top: 0.0, bottom: 8.0, left: 16.0, right: 16.0),
          child: Row(
            children: [
              // 1. Гарчиг текст
              const Text(
                'Үйлчилгээ', // <<--- ГАРЧИГ: "Үйлчилгээ"
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),

              const SizedBox(width: 8),
              // 2. Зураас
              Expanded(child: Divider(color: Colors.grey, height: 1, thickness: 1)),
            ],
          ),
        ),
        // Bottom Half: Home Buttons Grid (including the map button)
        Expanded(
          flex: 7, // Represents 60%
          child: _buildHomeButtonsGrid(),
        ),
      ],
    );
  }

  // And the helper method (if you choose to use it):
  Widget _buildHomeButtonsGrid() {
    return _HomeButtonsGrid(
      // Pass the fetchRoom method as the required callback
      onMapTap: fetchRoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final orientation = MediaQuery.of(context).orientation;
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isHistoryScreen = appBarCaption == 'Өвчний түүх';
    final isLandscape = orientation == Orientation.landscape;
    debugPrint('screenWidth: $shortestSide, orientation: $orientation, platform: $platform');
    final isCompactIOS = platform == TargetPlatform.iOS && shortestSide < 600;
    final shouldHideAppBar = isHistoryScreen && isLandscape && isCompactIOS;

    final appBarWidget =
        shouldHideAppBar
            ? null
            : AppBar(
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
            );

    return Scaffold(
      appBar: appBarWidget,
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

// Add the new _HomeButtonsGrid widget
class _HomeButtonsGrid extends StatefulWidget {
  // 1. Define the callback function signature
  final VoidCallback onMapTap;

  const _HomeButtonsGrid({required this.onMapTap, super.key});

  @override
  State<_HomeButtonsGrid> createState() => _HomeButtonsGridState();
}
// In main.dart

class _HomeButtonsGridState extends State<_HomeButtonsGrid> {
  // Use the actual DAO provided in home_dao.dart
  final _homeDao = HomeDAO();

  // The list will hold maps where 'icon' is a String name and 'navigate' is the destination
  List<Map<String, String>> _buttons = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchButtons();
  }

  Future<void> _fetchButtons() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiResponse = await _homeDao.getHomeButtons();

      if (apiResponse.success && apiResponse.data != null) {
        _buttons =
            (apiResponse.data as List<dynamic>).map((e) => Map<String, String>.from(e)).toList();
      }
    } catch (e) {
      _errorMessage = 'Учирсан алдаа: ${e.toString()}.';
      debugPrint('Error fetching home buttons: $e');
    } finally {
      // 🎯 FIX: Always insert the map button at index 0, regardless of API response.
      _buttons.insert(0, {"label": "Газрын зураг харах", "icon": "Map", "navigate": "map"});

      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handleNavigation(String navigateTo, String label) async {
    // Logic for navigation based on 'navigate' value
    debugPrint('Navigating to: $navigateTo');

    // Get the state of the parent MyHomePage widget
    final parentState = context.findAncestorStateOfType<_MyHomePageState>();
    if (parentState == null) return;

    // ❌ The 'map' logic was REMOVED from here because it is now handled
    //    directly in the 'build' method's ElevatedButton logic for the map button.

    if (navigateTo == 'order') {
      // Navigate to TimeOrderScreen (BottomNav index 1) by changing the index
      parentState._onItemTapped(1);
    } else if (navigateTo.startsWith('/history')) {
      // 1. Extract the historyKey
      final uri = Uri.parse(navigateTo);
      final historyKey = uri.queryParameters['historyKey'];

      // 2. Set the key in the parent's state
      parentState.setState(() {
        parentState._historyKeyFromHome = historyKey;
      });

      // 3. Change the tab index
      parentState._onItemTapped(3);

      debugPrint('History Key set in parent state and tab switched: $historyKey');
    } else if (navigateTo.startsWith('map')) {
      widget.onMapTap();
    }
  }
  // Simple mapping from icon name string to an actual IconData
  // Since Dart doesn't allow dynamic lookup of static Icon properties,
  // we must keep the mapping for the strings provided by the API (like 'InsertInvitation').

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'InsertInvitation':
        return Icons.insert_invitation;
      case 'Medication':
        return Icons.medication;
      case 'Biotech':
        return Icons.biotech;
      case 'SensorOccupied':
        return Icons.sensor_occupied;
      case 'Vaccines':
        return Icons.vaccines;
      case 'Map':
        return Icons.map;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Алдаа: $_errorMessage',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, // 2 columns
          crossAxisSpacing: 10.0,
          mainAxisSpacing: 10.0,
          childAspectRatio: 1.6, // 💡 Өндрийг багасгахын тулд 1.5-аас 2.0 болгож өөрчлөв
        ),
        itemCount: _buttons.length,
        itemBuilder: (context, index) {
          final buttonData = _buttons[index];
          final label = buttonData['label']!;
          final navigateTo = buttonData['navigate']!;
          final iconData = _getIconData(buttonData['icon']!);

          return ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                // side: const BorderSide(color: Colors.black, width: 0.3), // <-- outline
              ),
              elevation: 0.5,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            ),
            onPressed: () => _handleNavigation(navigateTo, label),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(iconData, size: 30),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
              ],
            ),
          );
        },
      ),
    );
  }
}
