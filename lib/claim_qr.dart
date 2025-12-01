import 'package:flutter/material.dart';
import 'package:medsoft_patient/api/auth_dao.dart';
import 'package:medsoft_patient/main.dart';

class ClaimQRScreen extends StatefulWidget {
  final String token;
  const ClaimQRScreen({super.key, required this.token});

  @override
  State<ClaimQRScreen> createState() => _ClaimQRScreenState();

}

class _ClaimQRScreenState extends State<ClaimQRScreen> {
  final _authDao = AuthDAO();
  bool _isLoading = false;

  Future<void> _claim() async {
    setState(() => _isLoading = true);

    final response = await _authDao.claimQR(widget.token);

    if (!mounted) return;

    if (response.success) {
      debugPrint("Claim success: ${response.message}");

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MyHomePage()),
        (route) => false,
      );
    } else {
      debugPrint("Claim failed: ${response.statusCode} - ${response.message}");

      setState(() {
        _isLoading = false;
      });

      final errorMessage = response.message ?? "Баталгаажуулалт амжилтгүй боллоо.";

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage), backgroundColor: Colors.red));
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
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                child:
                    _isLoading
                        ? Row(
                          key: const ValueKey('loading'),
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                            SizedBox(width: 12),
                            Text("Уншиж байна...", style: TextStyle(fontSize: 18)),
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
                          MaterialPageRoute(builder: (_) => const MyHomePage()),
                        );
                      },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
              child: const Text("Татгалзах", style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
