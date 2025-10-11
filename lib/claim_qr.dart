import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:medsoft_patient/constants.dart';
import 'package:medsoft_patient/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClaimQRScreen extends StatefulWidget {
  final String token;
  const ClaimQRScreen({super.key, required this.token});

  @override
  State<ClaimQRScreen> createState() => _ClaimQRScreenState();
}

class _ClaimQRScreenState extends State<ClaimQRScreen> {
  bool _isLoading = false;

  Future<void> _claim() async {
    bool claimSuccessful = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final tokenSaved = prefs.getString('X-Medsoft-Token') ?? '';
      final server = prefs.getString('X-Tenant') ?? '';

      final headers = {"Authorization": "Bearer $tokenSaved"};
      debugPrint('widget.token: ${widget.token}');
      final response = await http.get(
        Uri.parse("${Constants.appUrl}/qr/claim?id=${widget.token}"),
        headers: headers,
      );

      if (response.statusCode == 200) {
        log("Claim success: ${response.body}");
        claimSuccessful = true;
      } else {
        log("Claim failed: ${response.statusCode}");
      }
    } catch (e) {
      log("Error calling claim API: $e");
    }

    if (!mounted) return;

    if (claimSuccessful) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const MyHomePage(title: 'Дуудлагын жагсаалт'),
        ),
        (route) => false,
      );
    } else {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Баталгаажуулалт амжилтгүй боллоо."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("QR баталгаажуулах")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Энэ QR токенийг баталгаажуулах уу?",
              style: TextStyle(fontSize: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),

            ElevatedButton(
              onPressed:
                  _isLoading
                      ? null
                      : () {
                        setState(() => _isLoading = true);
                        Future.microtask(() => _claim());
                      },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 15,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder:
                    (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                child:
                    _isLoading
                        ? Row(
                          key: const ValueKey('loading'),
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              "Уншиж байна...",
                              style: TextStyle(fontSize: 18),
                            ),
                          ],
                        )
                        : const Text(
                          "Зөвшөөрөх",
                          key: ValueKey('text'),
                          style: TextStyle(fontSize: 18),
                        ),
              ),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed:
                  _isLoading
                      ? null
                      : () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => const MyHomePage(
                                  title: 'Дуудлагын жагсаалт',
                                ),
                          ),
                        );
                      },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 15,
                ),
              ),
              child: const Text("Татгалзах", style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
