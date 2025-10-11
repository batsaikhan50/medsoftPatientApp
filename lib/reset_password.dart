import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:medsoft_patient/constants.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _newPasswordConfirmController =
      TextEditingController();

  bool _isLoading = false;
  bool _isSendingOtp = false;
  bool _otpSent = false;
  bool _showPhoneError = false;

  bool get _isPhoneValid {
    final phone = _usernameController.text.trim();
    final regex = RegExp(r'^\d{8}$');
    return regex.hasMatch(phone);
  }

  Future<void> _sendOtp() async {
    if (!_isPhoneValid) {
      setState(() => _showPhoneError = true);
      return;
    }

    setState(() {
      _isSendingOtp = true;
      _showPhoneError = false;
    });

    final url = Uri.parse('${Constants.appUrl}/auth/otp');
    final body = jsonEncode({"username": _usernameController.text.trim()});

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      setState(() => _isSendingOtp = false);

      if (response.statusCode == 200) {
        setState(() => _otpSent = true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('OTP илгээгдлээ.')));
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Алдаа: ${data['message'] ?? response.body}')),
        );
      }
    } catch (e) {
      setState(() => _isSendingOtp = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Сүлжээний алдаа: $e')));
    }
  }

  Future<void> _resetPassword() async {
    final username = _usernameController.text.trim();
    final otp = _otpController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final newPasswordConfirm = _newPasswordConfirmController.text.trim();

    if (username.isEmpty ||
        otp.isEmpty ||
        newPassword.isEmpty ||
        newPasswordConfirm.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Бүх талбарыг бөглөнө үү.')));
      return;
    }

    if (newPassword != newPasswordConfirm) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Нууц үг таарахгүй байна.')));
      return;
    }

    setState(() => _isLoading = true);

    final url = Uri.parse('${Constants.appUrl}/auth/reset/password');
    final body = jsonEncode({
      "username": username,
      "newPassword": newPassword,
      "newPasswordConfirm": newPasswordConfirm,
      "otp": otp,
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нууц үг амжилттай шинэчлэгдлээ.')),
        );
        Navigator.pop(context);
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Алдаа: ${data['message'] ?? response.body}')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Сүлжээний алдаа: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(() {
      if (_showPhoneError && _isPhoneValid) {
        setState(() => _showPhoneError = false);
      } else {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF00CCCC),
        title: const Text('Нууц үг сэргээх'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _usernameController,
              keyboardType: TextInputType.phone,
              maxLength: 8,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: const InputDecoration(
                labelText: 'Утасны дугаар (8 оронтой)',
                counterText: '',
              ),
              onChanged: (value) {
                setState(() {
                  if (_showPhoneError && _isPhoneValid) {
                    _showPhoneError = false;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Шинэ нууц үг'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPasswordConfirmController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Шинэ нууц үг давтах',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      TextField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'OTP код (6 оронтой)',
                          counterText: '',
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: ElevatedButton.icon(
                            onPressed: (!_isSendingOtp) ? _sendOtp : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  _isPhoneValid
                                      ? const Color(0xFFFFE0B2)
                                      : Colors.grey[300],
                              foregroundColor:
                                  _isPhoneValid
                                      ? const Color(0xFF8C4A00)
                                      : Colors.grey[500],
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon:
                                _isSendingOtp
                                    ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF8C4A00),
                                      ),
                                    )
                                    : const Icon(Icons.send, size: 20),
                            label: Text(
                              _isSendingOtp ? ' ' : 'OTP илгээх',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_showPhoneError) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Утасны дугаараа оруулсны дараа OTP илгээнэ үү.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (!_otpSent || _isLoading) ? null : _resetPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00CCCC),
                ),
                child:
                    _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Болсон'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
