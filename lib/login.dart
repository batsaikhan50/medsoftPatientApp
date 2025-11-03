import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keyboard_actions/keyboard_actions.dart';
import 'package:medsoft_patient/api/auth_dao.dart';
import 'package:medsoft_patient/claim_qr.dart';
import 'package:medsoft_patient/main.dart';
import 'package:medsoft_patient/reset_password.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  final String? fcmToken; // 🔸 receive it here
  const LoginScreen({super.key, this.fcmToken});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _authDao = AuthDAO();

  final TextEditingController _usernameLoginController = TextEditingController();
  final TextEditingController _passwordLoginController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _passwordCheckController = TextEditingController();
  // final TextEditingController _regNoController = TextEditingController();
  final TextEditingController _regNoNumberController = TextEditingController();
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
  final FocusNode _regNoLetterFocus = FocusNode();
  final FocusNode _regNoFocus = FocusNode();
  final FocusNode _firstnameFocus = FocusNode();
  final FocusNode _lastnameFocus = FocusNode();
  String? _regNoFirstLetter;
  String? _regNoSecondLetter;
  final List<String> _mongolianCyrillicLetters = [
    'А',
    'Б',
    'В',
    'Г',
    'Д',
    'Е',
    'Ё',
    'Ж',
    'З',
    'И',
    'Й',
    'К',
    'Л',
    'М',
    'Н',
    'О',
    'Ө',
    'П',
    'Р',
    'С',
    'Т',
    'У',
    'Ү',
    'Ф',
    'Х',
    'Ц',
    'Ч',
    'Ш',
    'Щ',
    'Ъ',
    'Ы',
    'Ь',
    'Э',
    'Ю',
    'Я',
  ];
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _usernameLoginController.dispose();
    _passwordLoginController.dispose();
    _usernameController.dispose();
    _passwordController.removeListener(_updatePasswordRules);
    _passwordCheckController.removeListener(_updatePasswordRules);
    _passwordController.dispose();
    _passwordCheckController.dispose();
    _regNoNumberController.dispose();

    _regNoNumberController.dispose();
    _firstnameFocus.dispose();
    _lastnameFocus.dispose();
    _codeController.dispose();
    _codeFocus.dispose();
    _usernameFocus.dispose();
    _passwordLoginFocus.dispose();
    _passwordFocus.dispose();
    _passwordCheckFocus.dispose();
    _scrollController.dispose();
    _regNoLetterFocus.dispose();
    _regNoFocus.dispose();
    super.dispose();
  }

  bool _isLoading = false;

  String _errorMessage = '';

  bool _isPasswordLoginVisible = false;
  bool _isPasswordVisible = false;
  bool _isPasswordCheckVisible = false;
  int _selectedToggleIndex = 0;
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
    final bottomInset = WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom;
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
    bool isGotMedsoftToken = xMedsoftServer != null && xMedsoftServer.isNotEmpty;

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

    _usernameLoginController.addListener(() {
      setState(() {});
    });

    _usernameController.addListener(() {
      setState(() {});
    });

    _passwordLoginController.addListener(() {
      setState(() {});
      _updatePasswordRules();
    });

    _passwordController.addListener(() {
      setState(() {});
      _updatePasswordRules();
    });

    _passwordCheckController.addListener(() {
      setState(() {});
      _updatePasswordRules();
    });

    // _regNoController.addListener(() {
    //   setState(() {});
    //   _validateRegNo();
    // });

    _regNoNumberController.addListener(() {
      setState(() {});
      _validateRegNo();
    });

    _firstnameController.addListener(() {
      setState(() {});
    });

    _lastnameController.addListener(() {
      setState(() {});
    });

    _dragPosition =
        _selectedToggleIndex *
        ((MediaQueryData.fromView(
                  WidgetsBinding.instance.platformDispatcher.views.first,
                ).size.width -
                32 -
                8) /
            2);

    _getInitialScreenString();
  }

  void _validateRegNo() {
    // final regNo = _regNoController.text.trim().toUpperCase();
    final firstLetter = _regNoFirstLetter ?? '';
    final secondLetter = _regNoSecondLetter ?? '';
    final numberPart = _regNoNumberController.text.trim();
    final regNo = firstLetter + secondLetter + numberPart;

    setState(() {
      if (regNo.isEmpty) {
        _regNoValidationError = null;
      } else if (firstLetter.isEmpty || secondLetter.isEmpty) {
        _regNoValidationError = 'Регистрын дугаарын үсгийг сонгоно уу';
      } else if (numberPart.length != 8) {
        _regNoValidationError = 'Регистрын дугаарын тоо 8 оронтой байх ёстой';
      } else if (!_regNoRegex.hasMatch(regNo)) {
        _regNoValidationError = 'Регистрын дугаар буруу байна';
      } else {
        _regNoValidationError = null;
      }
    });
  }

  bool _validateRegisterInputs() {
    final password = _passwordController.text;
    final passwordMatchError = _validatePasswordMatch(password, _passwordCheckController.text);
    final rules = _validatePasswordRules(password);

    // ⚠️ UPDATED logic to combine letters and number field for validation
    final firstLetter = _regNoFirstLetter ?? '';
    final secondLetter = _regNoSecondLetter ?? '';
    final numberPart = _regNoNumberController.text.trim();
    final regNo = firstLetter + secondLetter + numberPart;

    if (firstLetter.isEmpty ||
        secondLetter.isEmpty ||
        numberPart.isEmpty ||
        !_regNoRegex.hasMatch(regNo)) {
      _regNoValidationError = 'Регистрын дугаарыг бүрэн зөв оруулна уу';
    } else {
      _regNoValidationError = null;
    }

    setState(() {
      _passwordRulesStatus = rules;
      _passwordCheckValidationError = passwordMatchError;
    });

    final allPassed = rules.values.every((passed) => passed == true);
    return allPassed && passwordMatchError == null && _regNoValidationError == null;
  }

  Future<void> _register() async {
    setState(() => _isLoading = true);

    // ⚠️ UPDATED: Combine the parts for the 'regNo' field in the body
    final regNo =
        (_regNoFirstLetter ?? '') + (_regNoSecondLetter ?? '') + _regNoNumberController.text;

    final body = {
      'username': _usernameController.text,
      'password': _passwordController.text,
      'passwordConfirm': _passwordCheckController.text,
      'regNo': regNo, // ⚠️ UPDATED
      'firstname': _firstnameController.text,
      'lastname': _lastnameController.text,
      'type': 'patient',
    };

    final response = await _authDao.register(body);

    if (response.success) {
      final prefs = await SharedPreferences.getInstance();
      prefs.clear();

      setState(() {
        _selectedToggleIndex = 0;
        _dragPosition = 0.0;
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = 'Бүртгэл амжилтгүй боллоо: ${response.message ?? "Тодорхойгүй алдаа"}';
        _isLoading = false;
      });
    }
  }

  Future<String?> getSavedToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('scannedToken');
  }

  Future<void> callWaitApi(BuildContext context, String token) async {
    try {
      final waitResponse = await _authDao.waitQR(token);
      if (waitResponse.success) {
        if (!context.mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ClaimQRScreen(token: token)),
        );
      } else {
        debugPrint("Login Wait failed (DAO): ${waitResponse.message ?? 'Unknown error'}");
      }
    } catch (e) {
      debugPrint('Error calling wait API: $e');
    }
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);

    debugPrint("FCM Token received in LoginScreen: ${widget.fcmToken}");

    final body = {
      'username': _usernameLoginController.text,
      'password': _passwordLoginController.text,
      'type': 'driver',
      'deviceToken': widget.fcmToken,
    };

    final response = await _authDao.login(body);

    if (response.success && response.data != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);

      final token = response.data!['token'];
      await prefs.setString('X-Medsoft-Token', token);
      await prefs.setString('Username', _usernameLoginController.text);
      await prefs.setString('Lastname', response.data!['user']['lastname']);
      await prefs.setString('Firstname', response.data!['user']['firstname']);
      await prefs.setString('RegNo', response.data!['user']['regNo']);

      _loadSharedPreferencesData();

      final savedToken = await getSavedToken();
      if (savedToken != null) {
        debugPrint("Login successful — calling wait API with savedToken: $savedToken");
        await _authDao.waitQR(savedToken);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => MyHomePage(title: 'Дуудлагын жагсаалт')),
        );
        return;
      }

      setState(() => _isLoading = false);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => MyHomePage(title: 'Дуудлагын жагсаалт')),
      );
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', false);
      setState(() {
        _errorMessage =
            response.message ?? 'Нэвтрэх нэр эсвэл нууц үг буруу байна. Дахин оролдоно уу.';
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
        debugPrint("trouble key: $key");
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
      'Нууц үгэнд дор хаяж нэг тоо байх ёстой': password.contains(RegExp(r'\d')),
      'Нууц үгэнд дор хаяж нэг жижиг үсэг байх ёстой': password.contains(RegExp(r'[a-z]')),
      'Нууц үгэнд дор хаяж нэг том үсэг байх ёстой': password.contains(RegExp(r'[A-Z]')),
      'Нууц үгэнд дор хаяж нэг тусгай тэмдэгт байх ёстой': password.contains(
        RegExp(r"[!@#&()\[\]{}:;',?/*~$^+=<>]"),
      ),
      'Нууц үгийн урт 10-35 тэмдэгт байх ёстой': password.length >= 10 && password.length <= 35,
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
                                color: isSelected ? Colors.white : Colors.black87,
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
    const Color iosToolbarColor = Color(0x00D8D7DE);

    return KeyboardActionsConfig(
      keyboardActionsPlatform: KeyboardActionsPlatform.ALL,
      nextFocus: true,
      keyboardBarColor: iosToolbarColor,
      actions: [
        if (_selectedToggleIndex == 0)
          KeyboardActionsItem(
            focusNode: _usernameLoginFocus,
            displayArrows: true,
            displayDoneButton: false,
          ),
        KeyboardActionsItem(
          focusNode: _passwordLoginFocus,
          displayArrows: true,
          displayDoneButton: false,
        ),
        if (_selectedToggleIndex == 1) ...[
          KeyboardActionsItem(
            focusNode: _usernameFocus,
            displayArrows: true,
            displayDoneButton: false,
          ),
          KeyboardActionsItem(
            focusNode: _passwordFocus,
            displayArrows: true,
            displayDoneButton: false,
          ),
          KeyboardActionsItem(
            focusNode: _passwordCheckFocus,
            displayArrows: true,
            displayDoneButton: false,
          ),
          KeyboardActionsItem(
            focusNode: _regNoLetterFocus, // The 8-digit number field
            displayArrows: false,
            displayDoneButton: false,
          ),
          KeyboardActionsItem(
            focusNode: _regNoFocus,
            displayArrows: true,
            displayDoneButton: false,
          ),
          KeyboardActionsItem(
            focusNode: _lastnameFocus,
            displayArrows: true,
            displayDoneButton: false,
          ),
          KeyboardActionsItem(
            focusNode: _firstnameFocus,
            displayArrows: true,
            displayDoneButton: false,
          ),
        ],
      ],
    );
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

  Widget _buildRegNoLetterPicker({
    required String? currentValue,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: currentValue,
      focusNode: _regNoLetterFocus,
      decoration: InputDecoration(
        isDense: true,
        // ⬅️ FIX: Increased vertical padding to match the height of 'Овог' field (vertical: 15)
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.arrow_drop_down, size: 20),
      style: const TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.bold),
      dropdownColor: Colors.white,
      items:
          _mongolianCyrillicLetters
              .map(
                (letter) => DropdownMenuItem(
                  value: letter,
                  child: Center(
                    child: Text(letter, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              )
              .toList(),
      onChanged: (String? newValue) {
        onChanged(newValue);
        _validateRegNo();
      },
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
        top: MediaQuery.of(context).size.shortestSide >= 600 ? 200 : 20,
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
                      prefixIcon: const Icon(Icons.phone),
                      suffixIcon:
                          _usernameLoginController.text.isNotEmpty
                              ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _usernameLoginController.clear();
                                },
                              )
                              : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                      prefixIcon: const Icon(Icons.phone),
                      suffixIcon:
                          _usernameController.text.isNotEmpty
                              ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _usernameController.clear();
                                },
                              )
                              : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_passwordLoginController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _passwordLoginController.clear();
                                setState(() {});
                              },
                            ),
                          IconButton(
                            icon: Icon(
                              _isPasswordLoginVisible ? Icons.visibility : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordLoginVisible = !_isPasswordLoginVisible;
                              });
                            },
                          ),
                        ],
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_passwordController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _passwordController.clear();
                                setState(() {});
                              },
                            ),
                          IconButton(
                            icon: Icon(
                              _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                        ],
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                                    color: entry.value ? Colors.green : Colors.red,
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
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_passwordCheckController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _passwordCheckController.clear();
                                setState(() {});
                              },
                            ),
                          IconButton(
                            icon: Icon(
                              _isPasswordCheckVisible ? Icons.visibility : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordCheckVisible = !_isPasswordCheckVisible;
                              });
                            },
                          ),
                        ],
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      errorText: _passwordCheckValidationError,
                    ),
                  ),

                if (_selectedToggleIndex == 1) const SizedBox(height: 10),

                // if (_selectedToggleIndex == 1)
                //   TextFormField(
                //     controller: _regNoController,
                //     focusNode: _regNoFocus,
                //     textInputAction: TextInputAction.next,
                //     decoration: InputDecoration(
                //       labelText: 'Регистрын дугаар',
                //       prefixIcon: const Icon(Icons.badge),
                //       suffixIcon:
                //           _regNoController.text.isNotEmpty
                //               ? IconButton(
                //                 icon: const Icon(Icons.clear),
                //                 onPressed: () {
                //                   _regNoController.clear();
                //                 },
                //               )
                //               : null,
                //       border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                //       errorText: _regNoValidationError,
                //     ),
                //     onChanged: (value) {
                //       _regNoController.value = _regNoController.value.copyWith(
                //         text: value.toUpperCase(),
                //         selection: TextSelection.collapsed(offset: value.length),
                //       );
                //     },
                //   ),
                if (_selectedToggleIndex == 1)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Manually add the Label
                      const Text(
                        'Регистрын дугаар',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Input Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // First Letter Picker
                          Expanded(
                            flex: 2, // Stable width for the letter
                            child: _buildRegNoLetterPicker(
                              currentValue: _regNoFirstLetter,
                              onChanged: (String? newValue) {
                                setState(() {
                                  _regNoFirstLetter = newValue;
                                });
                                _validateRegNo();
                              },
                            ),
                          ),
                          // ⬅️ FIX: Small 4-pixel gap to prevent border collision
                          const SizedBox(width: 4),
                          // Second Letter Picker
                          Expanded(
                            flex: 2, // Stable width for the letter
                            child: _buildRegNoLetterPicker(
                              currentValue: _regNoSecondLetter,
                              onChanged: (String? newValue) {
                                setState(() {
                                  _regNoSecondLetter = newValue;
                                });
                                _validateRegNo();
                              },
                            ),
                          ),
                          // ⬅️ FIX: Small 4-pixel gap
                          const SizedBox(width: 4),
                          Expanded(
                            flex: 5, // Keep the stable flex ratio
                            child: TextFormField(
                              controller: _regNoNumberController,
                              focusNode: _regNoFocus,
                              textInputAction: TextInputAction.next,
                              keyboardType: TextInputType.number,
                              maxLength: 8,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: InputDecoration(
                                hintText: '8 оронтой тоо',
                                counterText: '', // Hides the counter
                                isDense: true,
                                // ⬅️ FIX: Use the same increased vertical padding (vertical: 15)
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 15,
                                ),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                suffixIcon:
                                    _regNoNumberController.text.isNotEmpty
                                        ? IconButton(
                                          icon: const Icon(Icons.clear, size: 20),
                                          onPressed: () {
                                            _regNoNumberController.clear();
                                            _validateRegNo();
                                          },
                                        )
                                        : null,
                              ),
                              onChanged: (value) => _validateRegNo(),
                            ),
                          ),
                        ],
                      ),
                      // Manually add the Error Text
                      if (_regNoValidationError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                          child: Text(
                            _regNoValidationError!,
                            style: const TextStyle(color: Colors.deepOrange, fontSize: 12),
                          ),
                        ),
                    ],
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
                      suffixIcon:
                          _lastnameController.text.isNotEmpty
                              ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _lastnameController.clear();
                                },
                              )
                              : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      errorText: _lastnameValidationError,
                    ),
                    onChanged: (value) {
                      _lastnameController.value = _lastnameController.value.copyWith(
                        text: value,
                        selection: TextSelection.collapsed(offset: value.length),
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
                      suffixIcon:
                          _firstnameController.text.isNotEmpty
                              ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _firstnameController.clear();
                                },
                              )
                              : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      errorText: _firstnameValidationError,
                    ),
                    onChanged: (value) {
                      _firstnameController.value = _firstnameController.value.copyWith(
                        text: value,
                        selection: TextSelection.collapsed(offset: value.length),
                      );
                    },
                  ),

                if (_selectedToggleIndex == 1) const SizedBox(height: 20),

                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                  ),

                if (_selectedToggleIndex == 0)
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () async {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ResetPasswordScreen()),
                        );
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

                if (_selectedToggleIndex == 0) const SizedBox(height: 20),
                if (_selectedToggleIndex == 1) const SizedBox(height: 10),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _selectedToggleIndex == 0
                            ? const Color(0xFF009688)
                            : const Color(0xFF0077b3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                            _selectedToggleIndex == 0 ? 'НЭВТРЭХ' : 'БҮРТГҮҮЛЭХ',
                            style: const TextStyle(fontSize: 15, color: Colors.white),
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
