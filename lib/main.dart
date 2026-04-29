import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:medsoft_patient/api/auth_dao.dart';
import 'package:medsoft_patient/api/base_dao.dart';
import 'package:medsoft_patient/api/home_dao.dart';
import 'package:medsoft_patient/api/map_dao.dart';
import 'package:medsoft_patient/components/error_handler.dart';
import 'package:medsoft_patient/claim_qr.dart';
import 'package:medsoft_patient/constants.dart';
import 'package:medsoft_patient/guide.dart';
import 'package:medsoft_patient/history_screen.dart';
import 'package:medsoft_patient/login.dart';
import 'package:medsoft_patient/news.dart';
import 'package:medsoft_patient/notification/fcm_service.dart';
import 'package:medsoft_patient/notification/local_notification_service.dart';
import 'package:medsoft_patient/notification_screen.dart';
import 'package:medsoft_patient/call_manager.dart';
import 'package:medsoft_patient/connectivity_banner.dart';
import 'package:medsoft_patient/patient_call_screen.dart';
import 'package:medsoft_patient/profile_screen.dart';
import 'package:medsoft_patient/qr_scan_screen.dart';
import 'package:medsoft_patient/time_order/time_order_screen.dart';
import 'package:medsoft_patient/webview_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  CallManager.instance.init();

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  final fcmService = FCMService();
  await fcmService.initFCM();
  //test auto pull
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
      ],

      supportedLocales: const [Locale('en', ''), Locale('mn', '')],

      debugShowCheckedModeBanner: false,
      navigatorKey: CallManager.navigatorKey,
      builder: (context, child) => ConnectivityBanner(child: child!),
      routes: {'/call': (_) => const PatientCallScreen()},
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

    final appLinks = AppLinks();
    final initialUri = await appLinks.getInitialLink();
    debugPrint("IN MY MAIN'S _getInitialScreen initialLink: $initialUri");

    if (initialUri != null) {
      if (initialUri.pathSegments.isNotEmpty &&
          initialUri.pathSegments[0] == 'qr' &&
          initialUri.pathSegments.length > 1) {
        String token = initialUri.pathSegments[1];
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
      return const MyHomePage();
    } else {
      debugPrint('globalFCMToken in _getInitialScreen: $globalFCMToken');
      return LoginScreen(fcmToken: globalFCMToken);
    }
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.medsoft.medsoftpatient/location');

  final _authDao = AuthDAO();
  final _mapDao = MapDAO();

  int _selectedIndex = 0;
  String? _historyKeyFromHome;

  final List<String> _locationHistory = [];
  Map<String, dynamic> sharedPreferencesData = {};
  Map<String, dynamic>? roomInfo;
  int _homeRefreshCounter = 0;
  String? _errorMessage;
  Timer? _timer;
  bool _isDialogShowing = false;
  String appBarCaption = 'Медсофт';

  @override
  void initState() {
    super.initState();
    BaseDAO.setOnUnauthorized(_logOut);

    // SystemChrome.setPreferredOrientations([
    //   DeviceOrientation.portraitUp,
    //   DeviceOrientation.landscapeLeft,
    //   DeviceOrientation.landscapeRight,
    // ]);

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

    AppLinks().uriLinkStream.listen((uri) async {
      {
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
        _loadSharedPreferencesData();
        _sendXMedsoftTokenToAppDelegate();
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

  void _onItemTapped(int index) {
    if (index == 2) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const QrScanScreen())).then((
        _,
      ) {
        debugPrint("Returned from QR Screen");
      });
      return;
    }

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
        case 3:
          appBarCaption = 'Түүх';
          break;
        case 4:
          appBarCaption = 'Профайл';
          break;
      }
    });
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
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint("⚠️ Unauthorized. Logging out.");
        if (mounted) {
          _logOut();
        }
      }
    } catch (e) {
      debugPrint("❌ API error: $e");
    }
  }

  void _showDoneDialog() {
    _isDialogShowing = true;
    final context = CallManager.navigatorKey.currentState?.overlay?.context;
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
      _errorMessage = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('X-Medsoft-Token') ?? '';
    if (token.isEmpty) {
      setState(() {
        _errorMessage = 'Нэвтрэх эрх байхгүй байна. Дахин нэвтэрнэ үү.';
      });
      if (mounted) _logOut();
      return;
    }

    final response = await _mapDao.getRoomInfo();

    if (response.success && response.data is Map<String, dynamic>) {
      roomInfo = response.data;

      if (roomInfo!.containsKey('url') && roomInfo!.containsKey('roomId')) {
        final url = roomInfo!['url'] as String;
        final title = "Байршил";
        final roomId = roomInfo!['roomId'] as String;
        final tenantName = roomInfo!['serverName'] as String;

        await prefs.setString('currentRoomId', roomId);
        await prefs.setString('xTenant', tenantName);
        final roomIdNum = roomInfo!['_id'];

        await platform.invokeMethod('sendRoomIdToAppDelegate', {'roomId': roomId});

        if (!mounted) return;
        final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Байршлын мэдээлэл ашиглах'),
            content: const Text(
              'Medsoft Patient апп нь таны байршлын мэдээллийг түргэн тусламжийн машинтай хуваалцана.\n\n'
              '• Цуглуулах мэдээлэл: GPS байршил\n'
              '• Ашиглах зорилго: Түргэн тусламжийн маршрут хянах\n'
              '• Хуваалцах: Эмнэлгийн диспетчерийн систем\n'
              '• Горим: Дуудлага идэвхтэй үед тасралтгүй\n\n'
              'Үргэлжлүүлэхийн тулд "Зөвшөөрөх" товчийг дарна уу.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Болих'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Зөвшөөрөх'),
              ),
            ],
          ),
        );

        if (!mounted) return;
        if (accepted != true) return;

        await platform.invokeMethod('startLocationManagerAfterLogin');

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
          _errorMessage = null;
        });
      } else {
        setState(() {
          _errorMessage = 'Серверээс ирсэн мэдээлэл дутуу байна.';
        });
      }
    } else {
      setState(() {
        _errorMessage = response.message ?? 'Алдаа гарлаа. Дахин оролдоно уу.';
      });
    }

    if (_errorMessage != null && mounted) {
      final isCallError = _errorMessage! == 'Дуудлага байхгүй';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: isCallError ? Colors.black : Colors.red,
          content: Text(_errorMessage!, style: const TextStyle(color: Colors.white)),
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
      LocalNotificationService().showLogoutNotification();
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

    if (CallManager.instance.isConnected) {
      await CallManager.instance.disconnect();
    }

    prefs.clear();
    // try {
    //   await platform.invokeMethod('stopLocationUpdates');
    // } on PlatformException catch (e) {
    //   debugPrint("Failed to stop location updates: '${e.message}'.");
    // }
    if (mounted) {
      debugPrint('globalFCMToken at logout: $globalFCMToken');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen(fcmToken: globalFCMToken)),
      );
    }
  }

  Widget _buildLocationBody() {
    final mediaQuery = MediaQuery.of(context);
    final orientation = mediaQuery.orientation;
    final shortestSide = mediaQuery.size.shortestSide;
    final platform = Theme.of(context).platform;
    const double tabletBreakpoint = 600.0;

    final isTabletLandscape =
        shortestSide >= tabletBreakpoint && orientation == Orientation.landscape;

    final isPhoneLandscape =
        shortestSide < tabletBreakpoint && orientation == Orientation.landscape;

    final applyLandscapeLayout = isTabletLandscape || isPhoneLandscape;

    final isCompactIOS = platform == TargetPlatform.iOS && shortestSide < tabletBreakpoint;
    final isLandscape = orientation == Orientation.landscape;
    final double? maxWidth = isCompactIOS && isLandscape ? 700.0 : null;

    Widget content;

    if (applyLandscapeLayout) {
      content = Row(
        children: [
          Expanded(
            child: NewsFeedWidget(key: ValueKey(_homeRefreshCounter), isVerticalScroll: true),
          ),

          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 8.0, left: 16.0, right: 16.0),
                  child: Row(
                    children: [
                      const Text(
                        'Үйлчилгээ',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Divider(color: Colors.grey, height: 1, thickness: 1)),
                    ],
                  ),
                ),

                Expanded(child: _buildHomeButtonsGrid()),
              ],
            ),
          ),
        ],
      );
    } else {
      content = Column(
        children: [
          Expanded(flex: 4, child: NewsFeedWidget(key: ValueKey(_homeRefreshCounter))),

          Padding(
            padding: const EdgeInsets.only(top: 0.0, bottom: 8.0, left: 16.0, right: 16.0),
            child: Row(
              children: [
                const Text(
                  'Үйлчилгээ',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),

                const SizedBox(width: 8),

                Expanded(child: Divider(color: Colors.grey, height: 1, thickness: 1)),
              ],
            ),
          ),

          Expanded(flex: 7, child: _buildHomeButtonsGrid()),
        ],
      );
    }

    final body =
        maxWidth != null
            ? Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: content,
              ),
            )
            : content;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _homeRefreshCounter++;
        });
      },
      child: body,
    );
  }

  Widget _buildHomeButtonsGrid() {
    return _HomeButtonsGrid(
      key: ValueKey(_homeRefreshCounter),
      onMapTap: fetchRoom,
      onError: (message) {
        ErrorHandler.showSnackBar(context, message, isError: true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final orientation = MediaQuery.of(context).orientation;
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isHistoryScreen = appBarCaption == 'Түүх';
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
                IconButton(
                  icon: const Icon(Icons.videocam),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PatientCallScreen()),
                    );
                  },
                ),
                // Existing Notification Button
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
    debugPrint('_historyKeyFromHome: $_historyKeyFromHome');
    final List<Widget> widgetOptions = <Widget>[
      _buildLocationBody(),
      const TimeOrderScreen(),

      const SizedBox(),
      HistoryScreen(key: ValueKey(_historyKeyFromHome), initialHistoryKey: _historyKeyFromHome),
      ProfileScreen(onGuideTap: _navigateToGuideScreen, onLogoutTap: _logOut),
    ];

    return Scaffold(
      appBar: appBarWidget,
      drawer: _buildDrawer(),
      body: IndexedStack(index: _selectedIndex, children: widgetOptions),

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

class _HomeButtonsGrid extends StatefulWidget {
  final VoidCallback onMapTap;
  final Function(String)? onError;

  const _HomeButtonsGrid({super.key, required this.onMapTap, this.onError});

  @override
  State<_HomeButtonsGrid> createState() => _HomeButtonsGridState();
}

class _HomeButtonsGridState extends State<_HomeButtonsGrid> {
  final _homeDao = HomeDAO();

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
      } else {
        _errorMessage = apiResponse.message ?? 'Товчнуудыг ачаалахад алдаа гарлаа.';
        widget.onError?.call(_errorMessage!);
      }
    } catch (e) {
      _errorMessage = 'Товчнуудыг ачаалахад алдаа гарлаа: ${e.toString()}';
      debugPrint('Error fetching home buttons: $e');
      widget.onError?.call(_errorMessage!);
    } finally {
      _buttons.insert(0, {"label": "Газрын зураг харах", "icon": "Map", "navigate": "map"});

      //test
      // _buttons.addAll([
      //   {"label": "Эмийн жор", "icon": "Medication", "navigate": "/history?historyKey=prescription"},
      //   {"label": "Лаборатори", "icon": "Biotech", "navigate": "/history?historyKey=laboratory"},
      //   {"label": "Рентген зураг", "icon": "SensorOccupied", "navigate": "/history?historyKey=xray"},
      //   {"label": "Вакцин", "icon": "Vaccines", "navigate": "/history?historyKey=vaccine"},
      //   {"label": "Эмчийн цаг", "icon": "InsertInvitation", "navigate": "order"},
      //   {"label": "Даатгал", "icon": "HelpOutline", "navigate": "/history?historyKey=insurance"},
      // ]);
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handleNavigation(String navigateTo, String label) async {
    debugPrint('Navigating to: $navigateTo');

    final parentState = context.findAncestorStateOfType<_MyHomePageState>();
    if (parentState == null) return;

    if (navigateTo == 'order') {
      parentState._onItemTapped(1);
    } else if (navigateTo.startsWith('/history')) {
      final uri = Uri.parse(navigateTo);
      final historyKey = uri.queryParameters['historyKey'];

      parentState.setState(() {
        parentState._historyKeyFromHome = historyKey;
      });

      parentState._onItemTapped(3);

      debugPrint('History Key set in parent state and tab switched: $historyKey');
    } else if (navigateTo.startsWith('map')) {
      widget.onMapTap();
    }
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'InsertInvitation':
        return Icons.insert_invitation;
      case 'Medication':
        return Icons.medication;
      case 'Biotech':
      case 'biotech':
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
      return const LoadingIndicator(message: 'Товчнуудыг ачааллаж байна...');
    }

    if (_errorMessage != null) {
      return ErrorHandler.buildErrorWidget(_errorMessage!, () {
        _fetchButtons();
      });
    }

    const double maxWidth = 700.0;

    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isTablet = shortestSide >= 600.0;

    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    final shouldConstrainWidth = isTablet || isLandscape;

    final gridContent = GridView.builder(
      padding: EdgeInsets.symmetric(horizontal: 10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10.0,
        mainAxisSpacing: 10.0,
        childAspectRatio: 1.7,
      ),
      itemCount: _buttons.length,
      itemBuilder: (context, index) {
        final buttonData = _buttons[index];
        final label = buttonData['label']!;
        final navigateTo = buttonData['navigate']!;
        final iconData = _getIconData(buttonData['icon']!);

        const int maxChars = 36;
        String displayedLabel = label;

        if (label.length > maxChars) {
          // Truncate the string to the first (maxChars - 3) characters,
          // leaving room for '...'
          displayedLabel = '${label.substring(0, maxChars - 3)}...';
        }

        // Optional: Dynamically adjust font size for constrained views (from previous suggestion)
        final double baseFontSize = 14.0;
        final double constrainedFontSize = (isTablet || isLandscape) ? 12.0 : baseFontSize;

        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0.5,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          ),
          onPressed: () => _handleNavigation(navigateTo, label),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(iconData, size: 28),
              const SizedBox(height: 4),
              Text(
                // Use the truncated label
                displayedLabel,
                textAlign: TextAlign.center,
                // Using the dynamic font size to improve fit further
                style: TextStyle(fontSize: constrainedFontSize - 1, height: 1.1),
                maxLines: 2, // Added to prevent overflow if the word-wrapping is still tight
                overflow:
                    TextOverflow.ellipsis, // Fallback for very long single words or tight layouts
              ),
            ],
          ),
        );
      },
    );

    if (shouldConstrainWidth) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: gridContent,
        ),
      );
    } else {
      return gridContent;
    }
  }
}
