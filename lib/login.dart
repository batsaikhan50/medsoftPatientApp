import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:http/http.dart' as http;
import 'package:keyboard_actions/keyboard_actions.dart';
import 'package:medsoft_patient/constants.dart';
import 'package:medsoft_patient/main.dart';
import 'package:medsoft_patient/webview_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final TextEditingController _usernameLoginController =
      TextEditingController();
  final TextEditingController _passwordLoginController =
      TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _passwordCheckController =
      TextEditingController();
  final TextEditingController _regNoController = TextEditingController();
  final TextEditingController _firstnameController = TextEditingController();
  final TextEditingController _lastnameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final FocusNode _codeFocus = FocusNode();
  final FocusNode _usernameLoginFocus = FocusNode();
  final FocusNode _passwordLoginFocus = FocusNode();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _passwordCheckFocus = FocusNode();
  final FocusNode _regNoFocus = FocusNode();
  final FocusNode _firstnameFocus = FocusNode();
  final FocusNode _lastnameFocus = FocusNode();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _usernameLoginController.dispose();
    _passwordLoginController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordCheckController.dispose();
    _regNoController.dispose();
    _firstnameFocus.dispose();
    _lastnameFocus.dispose();
    _codeController.dispose();
    _codeFocus.dispose();
    _usernameFocus.dispose();
    _passwordLoginFocus.dispose();
    _passwordFocus.dispose();
    _passwordCheckFocus.dispose();
    _scrollController.dispose();
    _passwordController.removeListener(_updatePasswordRules);
    _passwordCheckController.removeListener(_updatePasswordRules);
    super.dispose();
  }

  bool _isLoading = false;

  String _errorMessage = '';

  bool _isPasswordLoginVisible = false;
  bool _isPasswordVisible = false;
  bool _isPasswordCheckVisible = false;
  int _selectedToggleIndex = 0; //0-Иргэн, 1-103
  double _dragPosition = 0.0;

  bool _isKeyboardVisible = false;

  Map<String, dynamic> sharedPreferencesData = {};

  Map<String, bool> _passwordRulesStatus = {};
  String? _passwordCheckValidationError;
  String? _regNoValidationError;
  String? _firstnameValidationError;
  String? _lastnameValidationError;

  final RegExp _regNoRegex = RegExp(
    r'^[А-ЯӨҮ]{2}[0-9]{2}(0[1-9]|1[0-2]|2[0-9]|3[0-2])(0[1-9]|[12][0-9]|3[01])[0-9]{2}$',
  );
  final RegExp mongolianCyrillicRegex = RegExp(r'^[А-Яа-яӨөҮүЁё]+$');

  String? username;

  @override
  void didChangeMetrics() {
    final bottomInset = WidgetsBinding.instance.window.viewInsets.bottom;
    final newValue = bottomInset > 0.0;

    if (_isKeyboardVisible != newValue) {
      setState(() {
        _isKeyboardVisible = newValue;
      });
    }
  }

  bool isMongolianCyrillic(String text) {
    return mongolianCyrillicRegex.hasMatch(text);
  }

  Future<void> _getInitialScreenString() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    String? xMedsoftServer = prefs.getString('X-Medsoft-Token');
    bool isGotMedsoftToken =
        xMedsoftServer != null && xMedsoftServer.isNotEmpty;

    String? username = prefs.getString('Username');
    bool isGotUsername = username != null && username.isNotEmpty;

    if (isLoggedIn && isGotMedsoftToken && isGotUsername) {
      debugPrint(
        'isLoggedIn: $isLoggedIn, isGotMedsoftToken: $isGotMedsoftToken, isGotUsername: $isGotUsername',
      );
    } else {
      return debugPrint("empty shared");
    }
  }

  Future<void> _fetchServerData() async {
    const url = 'https://runner-api.medsoft.care/api/gateway/servers';
    final headers = {'X-Token': Constants.xToken};

    try {
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true) {
          final List<Map<String, String>> serverNames =
              List<Map<String, String>>.from(
                data['data'].map<Map<String, String>>((server) {
                  return {
                    'name': server['name'].toString(),
                    'url': server['url'].toString(),
                  };
                }),
              );
        } else {
          setState(() {
            _errorMessage = 'Серверүүдийг ачааллахад амжилтгүй боллоо.';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Серверийн мэдээлэл авахад алдаа гарлаа.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Алдаа гарлаа: $e';
      });
    }
  }

  void _updatePasswordRules() {
    final password = _passwordController.text;
    final rules = _validatePasswordRules(password);

    setState(() {
      _passwordRulesStatus = rules;
      _passwordCheckValidationError = _validatePasswordMatch(
        password,
        _passwordCheckController.text,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _passwordController.addListener(_updatePasswordRules);
    _passwordCheckController.addListener(_updatePasswordRules);
    _regNoController.addListener(_validateRegNo);

    _dragPosition =
        _selectedToggleIndex *
        ((MediaQueryData.fromView(WidgetsBinding.instance.window).size.width -
                32 -
                8) /
            2);
    _fetchServerData();
    _getInitialScreenString();
  }

  void _validateRegNo() {
    final regNo = _regNoController.text.trim().toUpperCase();

    setState(() {
      if (regNo.isEmpty) {
        _regNoValidationError = null;
      } else if (!_regNoRegex.hasMatch(regNo)) {
        _regNoValidationError = 'Регистрын дугаар буруу байна';
      } else {
        _regNoValidationError = null;
      }
    });
  }

  void _validateName() {
    final firstname = _firstnameController.text.trim().toUpperCase();
    final lastname = _lastnameController.text.trim().toUpperCase();

    setState(() {
      if (firstname.isEmpty) {
        _firstnameValidationError = null;
      } else if (!mongolianCyrillicRegex.hasMatch(firstname)) {
        _firstnameValidationError = 'Кирилл үсгээр бичнэ үү.';
      } else {
        _firstnameValidationError = null;
      }

      if (lastname.isEmpty) {
        _lastnameValidationError = null;
      } else if (!mongolianCyrillicRegex.hasMatch(lastname)) {
        _lastnameValidationError = 'Кирилл буруу байна';
      } else {
        _lastnameValidationError = null;
      }
    });
  }

  bool _validateRegisterInputs() {
    final password = _passwordController.text;
    final passwordMatchError = _validatePasswordMatch(
      password,
      _passwordCheckController.text,
    );
    final rules = _validatePasswordRules(password);

    final regNo = _regNoController.text.trim().toUpperCase();
    if (regNo.isEmpty || !_regNoRegex.hasMatch(regNo)) {
      _regNoValidationError = 'Регистрын дугаар буруу байна';
    } else {
      _regNoValidationError = null;
    }

    setState(() {
      _passwordRulesStatus = rules;
      _passwordCheckValidationError = passwordMatchError;
    });

    final allPassed = rules.values.every((passed) => passed == true);
    return allPassed &&
        passwordMatchError == null &&
        _regNoValidationError == null;
  }

  Future<void> _register() async {
    setState(() {
      _isLoading = true;
    });

    final body = {
      'username': _usernameController.text,
      'password': _passwordController.text,
      'passwordConfirm': _passwordCheckController.text,
      'regNo': _regNoController.text,
      'firstname': _firstnameController.text,
      'lastname': _lastnameController.text,
      'type': 'patient',
    };

    final headers = {'Content-Type': 'application/json'};

    debugPrint('Request Headers: $headers');
    debugPrint('Request Body: ${json.encode(body)}');

    try {
      final response = await http.post(
        Uri.parse('https://app.medsoft.care/api/auth/signup'),
        headers: headers,
        body: json.encode(body),
      );

      debugPrint('Register response Status: ${response.statusCode}');
      debugPrint('Register response Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true) {
          SharedPreferences prefs = await SharedPreferences.getInstance();

          await prefs.setBool('isLoggedIn', false);
          await prefs.remove('X-Tenant');
          await prefs.remove('X-Medsoft-Token');
          await prefs.remove('Username');

          setState(() {
            _selectedToggleIndex = 0;
            _dragPosition = 0.0;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = 'Бүртгэл амжилтгүй боллоо: ${data['message']}';
            _isLoading = false;
          });
        }
      } else {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', false);
        setState(() {
          _errorMessage = 'Бүртгэх үед алдаа гарлаа. Дахин оролдоно уу.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Гэнэтийн алдаа: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
    });

    final body = {
      'username': _usernameLoginController.text,
      'password': _passwordLoginController.text,
      'type': 'driver',
    };
    final headers = {'Content-Type': 'application/json'};

    debugPrint('Request Headers: $headers');
    debugPrint('Request Body: ${json.encode(body)}');

    try {
      final response = await http.post(
        Uri.parse('https://app.medsoft.care/api/auth/login'),
        headers: headers,
        body: json.encode(body),
      );

      debugPrint('Response Status: ${response.statusCode}');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        if (!(Platform.environment['SIMULATOR_DEVICE_NAME'] ==
            'iPhone SE (3rd generation)')) {
          FlutterAppBadger.removeBadge();
        } else {}

        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true) {
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isLoggedIn', true);

          final String token = data['data']['token'];

          await prefs.setString('X-Medsoft-Token', token);
          await prefs.setString('Username', _usernameLoginController.text);

          _loadSharedPreferencesData();

          _isLoading = false;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => MainHomeScreen()),
          );
        } else {
          setState(() {
            _errorMessage = 'Нэвтрэхэд амжилтгүй боллоо: ${data['message']}';
            _isLoading = false;
          });
        }
      } else {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', false);
        setState(() {
          _errorMessage = 'Нэвтрэх үед алдаа гарлаа. Дахин оролдоно уу.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Алдаа гарлаа: $e';
        _isLoading = false;
      });
    }
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
      username = prefs.getString('Username');
      sharedPreferencesData = data;
    });
  }

  Map<String, bool> _validatePasswordRules(String password) {
    return {
      'Нууц үгэнд дор хаяж нэг тоо байх ёстой': password.contains(
        RegExp(r'\d'),
      ),
      'Нууц үгэнд дор хаяж нэг жижиг үсэг байх ёстой': password.contains(
        RegExp(r'[a-z]'),
      ),
      'Нууц үгэнд дор хаяж нэг том үсэг байх ёстой': password.contains(
        RegExp(r'[A-Z]'),
      ),
      'Нууц үгэнд дор хаяж нэг тусгай тэмдэгт байх ёстой': password.contains(
        RegExp(r"[!@#&()\[\]{}:;',?/*~$^+=<>]"),
      ),
      'Нууц үгийн урт 10-35 тэмдэгт байх ёстой':
          password.length >= 10 && password.length <= 35,
    };
  }

  String? _validatePasswordMatch(String password, String confirmPassword) {
    if (password != confirmPassword) {
      return 'Нууц үг таарахгүй байна';
    }
    return null;
  }

  Widget buildAnimatedToggle() {
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final screenWidth = MediaQuery.of(context).size.width;
    final toggleWidth = isTablet ? screenWidth * 0.5 : screenWidth - 32;
    final knobWidth = (toggleWidth - 8) / 2;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: toggleWidth),
        child: GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _dragPosition += details.delta.dx;
              _dragPosition = _dragPosition.clamp(0, knobWidth);
            });
          },
          onHorizontalDragEnd: (_) {
            setState(() {
              if (_dragPosition < (knobWidth / 2)) {
                _selectedToggleIndex = 0;
                _dragPosition = 0;
              } else {
                _selectedToggleIndex = 1;
                _dragPosition = knobWidth;
              }
            });
          },
          onTapDown: (details) {
            final dx = details.localPosition.dx;
            setState(() {
              if (dx < toggleWidth / 2) {
                _selectedToggleIndex = 0;
                _dragPosition = 0;
              } else {
                _selectedToggleIndex = 1;
                _dragPosition = knobWidth;
              }
            });
          },
          child: Container(
            height: 56,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(30),
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  left: _dragPosition,
                  top: 0,
                  bottom: 0,
                  width: knobWidth,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      color:
                          _selectedToggleIndex == 0
                              ? const Color(0xFF009688)
                              : const Color(0xFF0077b3),
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ),
                Row(
                  children: List.generate(2, (index) {
                    final label = index == 0 ? 'Нэвтрэх' : 'Бүртгүүлэх';
                    final isSelected = index == _selectedToggleIndex;

                    return Expanded(
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              index == 0 ? Icons.login : Icons.person_add,
                              color: isSelected ? Colors.white : Colors.black87,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              label,
                              style: TextStyle(
                                color:
                                    isSelected ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  KeyboardActionsConfig _buildKeyboardActionsConfig(BuildContext context) {
    return KeyboardActionsConfig(
      keyboardActionsPlatform: KeyboardActionsPlatform.ALL,
      nextFocus: true,
      keyboardBarColor: Colors.grey[200],
      actions: [
        if (_selectedToggleIndex == 0)
          KeyboardActionsItem(
            focusNode: _usernameLoginFocus,
            displayArrows: true,
            onTapAction: () => _scrollIntoView(_usernameLoginFocus),
          ),
        KeyboardActionsItem(
          focusNode: _passwordLoginFocus,
          displayArrows: true,
          onTapAction: () => _scrollIntoView(_passwordLoginFocus),
        ),
        if (_selectedToggleIndex == 1) ...[
          KeyboardActionsItem(
            focusNode: _usernameFocus,
            displayArrows: true,
            onTapAction: () => _scrollIntoView(_usernameFocus),
          ),
          KeyboardActionsItem(
            focusNode: _passwordFocus,
            displayArrows: true,
            onTapAction: () => _scrollIntoView(_passwordFocus),
          ),
          KeyboardActionsItem(
            focusNode: _passwordCheckFocus,
            displayArrows: true,
            onTapAction: () => _scrollIntoView(_passwordCheckFocus),
          ),
          KeyboardActionsItem(
            focusNode: _regNoFocus,
            displayArrows: true,
            onTapAction: () => _scrollIntoView(_regNoFocus),
          ),
          KeyboardActionsItem(
            focusNode: _lastnameFocus,
            displayArrows: true,
            onTapAction: () => _scrollIntoView(_lastnameFocus),
          ),
          KeyboardActionsItem(
            focusNode: _firstnameFocus,
            displayArrows: true,
            onTapAction: () => _scrollIntoView(_firstnameFocus),
          ),
        ],
      ],
    );
  }

  void _scrollIntoView(FocusNode focusNode) {
    final context = focusNode.context;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: KeyboardActions(
            config: _buildKeyboardActionsConfig(context),
            child: _buildLoginForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = isTablet ? screenWidth * 0.5 : double.infinity;

    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth),
          child: Form(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset('assets/icon/logoTransparent.png', height: 150),
                const Text(
                  'Тавтай морил',
                  style: TextStyle(
                    fontSize: 22.4,
                    color: Color(0xFF009688),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                buildAnimatedToggle(),
                const SizedBox(height: 20),

                if (_selectedToggleIndex == 0)
                  TextFormField(
                    controller: _usernameLoginController,
                    focusNode: _usernameLoginFocus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Утасны дугаар',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                if (_selectedToggleIndex == 1)
                  TextFormField(
                    controller: _usernameController,
                    focusNode: _usernameFocus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Утасны дугаар',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),

                if (_selectedToggleIndex == 0)
                  TextFormField(
                    controller: _passwordLoginController,
                    focusNode: _passwordLoginFocus,
                    textInputAction: TextInputAction.done,
                    obscureText: !_isPasswordLoginVisible,
                    decoration: InputDecoration(
                      labelText: 'Нууц үг',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordLoginVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordLoginVisible = !_isPasswordLoginVisible;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                if (_selectedToggleIndex == 0) const SizedBox(height: 20),

                if (_selectedToggleIndex == 1)
                  TextFormField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    textInputAction: TextInputAction.done,
                    obscureText: !_isPasswordVisible,
                    decoration: InputDecoration(
                      labelText: 'Нууц үг',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                if (_selectedToggleIndex == 1 &&
                    _passwordController.text.isNotEmpty &&
                    _passwordRulesStatus.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:
                        _passwordRulesStatus.entries.map((entry) {
                          return Row(
                            children: [
                              Icon(
                                entry.value ? Icons.check_circle : Icons.cancel,
                                color: entry.value ? Colors.green : Colors.red,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color:
                                        entry.value ? Colors.green : Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                  ),

                if (_selectedToggleIndex == 1) const SizedBox(height: 20),

                if (_selectedToggleIndex == 1)
                  TextFormField(
                    controller: _passwordCheckController,
                    focusNode: _passwordCheckFocus,
                    textInputAction: TextInputAction.done,
                    obscureText: !_isPasswordCheckVisible,
                    decoration: InputDecoration(
                      labelText: 'Нууц үг давтах',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordCheckVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordCheckVisible = !_isPasswordCheckVisible;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      errorText: _passwordCheckValidationError,
                    ),
                  ),

                if (_selectedToggleIndex == 1) const SizedBox(height: 20),

                if (_selectedToggleIndex == 1)
                  TextFormField(
                    controller: _regNoController,
                    focusNode: _regNoFocus,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Регистрын дугаар',
                      prefixIcon: const Icon(Icons.badge),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      errorText: _regNoValidationError,
                    ),
                    onChanged: (value) {
                      _regNoController.value = _regNoController.value.copyWith(
                        text: value.toUpperCase(),
                        selection: TextSelection.collapsed(
                          offset: value.length,
                        ),
                      );
                    },
                  ),

                if (_selectedToggleIndex == 1) const SizedBox(height: 20),

                if (_selectedToggleIndex == 1)
                  TextFormField(
                    controller: _lastnameController,
                    focusNode: _lastnameFocus,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Овог',
                      prefixIcon: const Icon(Icons.badge),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      errorText: _lastnameValidationError,
                    ),
                    onChanged: (value) {
                      _lastnameController.value = _lastnameController.value
                          .copyWith(
                            text: value,
                            selection: TextSelection.collapsed(
                              offset: value.length,
                            ),
                          );
                    },
                  ),

                if (_selectedToggleIndex == 1) const SizedBox(height: 20),

                if (_selectedToggleIndex == 1)
                  TextFormField(
                    controller: _firstnameController,
                    focusNode: _firstnameFocus,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Нэр',
                      prefixIcon: const Icon(Icons.badge),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      errorText: _firstnameValidationError,
                    ),
                    onChanged: (value) {
                      _firstnameController.value = _firstnameController.value
                          .copyWith(
                            text: value,
                            selection: TextSelection.collapsed(
                              offset: value.length,
                            ),
                          );
                    },
                  ),

                if (_selectedToggleIndex == 1) const SizedBox(height: 20),

                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),

                if (_selectedToggleIndex == 1)
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () async {
                        SharedPreferences prefs =
                            await SharedPreferences.getInstance();
                        String? baseUrl = prefs.getString('forgetUrl');

                        if (baseUrl != null && baseUrl.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => WebViewScreen(
                                    url:
                                        '$baseUrl/forget?callback=medsoftpatient://callback',
                                    title: '',
                                  ),
                            ),
                          );
                        } else {
                          setState(() {
                            _errorMessage =
                                'Нууц үг солихын тулд эмнэлэг сонгоно уу.';
                          });
                        }
                      },
                      child: const Text(
                        'Нууц үг мартсан?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF009688),
                        ),
                      ),
                    ),
                  ),

                if (_selectedToggleIndex == 1) const SizedBox(height: 10),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _selectedToggleIndex == 0
                            ? const Color(0xFF009688)
                            : const Color(0xFF0077b3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(double.infinity, 40),
                  ),
                  onPressed:
                      _isLoading
                          ? null
                          : () {
                            if (_selectedToggleIndex == 1) {
                              if (_validateRegisterInputs()) {
                                _register();
                              }
                            } else {
                              _login();
                            }
                          },
                  child:
                      _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                            _selectedToggleIndex == 0
                                ? 'НЭВТРЭХ'
                                : 'БҮРТГҮҮЛЭХ',
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
