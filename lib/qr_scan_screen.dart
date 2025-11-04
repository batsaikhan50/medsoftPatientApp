import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medsoft_patient/api/auth_dao.dart';
import 'package:medsoft_patient/claim_qr.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  final _authDAO = AuthDAO();
  QRViewController? controller;
  bool isScanned = false;
  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    // 1. Lock to Portrait when the screen is initialized
    // SystemChrome.setPreferredOrientations([
    //   DeviceOrientation.portraitUp,
    //   DeviceOrientation.portraitDown,
    // ]);
  }

  @override
  void dispose() {
    // 2. Reset orientation to allow all directions when the screen is disposed
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    controller?.dispose();
    super.dispose();
  }
  // @override
  // void dispose() {
  //   controller?.dispose();
  //   super.dispose();
  // }

  Future<void> _handleScannedToken(String url) async {
    // try {
    Uri uri = Uri.parse(url);
    String? token;
    if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == "qr") {
      token = uri.pathSegments[1];
    }

    if (token == null) {
      debugPrint("Invalid QR format");

      // Ensure camera resumes even on invalid local format
      if (controller != null) await controller!.resumeCamera();
      setState(() => isScanned = false);
      return;
    }

    debugPrint("Extracted token: $token");

    final response = await _authDAO.waitQR(token);

    if (response.statusCode == 200) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => ClaimQRScreen(token: token!)),
      );
    } else {
      debugPrint("Wait API failed: ${response.statusCode}");

      // --- FIX: Camera Unfreeze and Error Handling ---

      final errorMessage = "Error: Status Code ${response.message}"; // Fallback message

      // 1. Show SnackBar with the error message
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage), backgroundColor: Colors.red));
      }

      // 2. Unfreeze the Camera and Reset State
      if (controller != null) {
        // Use the non-null assertion operator (!) to satisfy the analyzer
        await controller!.resumeCamera();
        debugPrint("Camera resumed after API failure.");
      }

      // Reset the flag to allow rescanning
      setState(() => isScanned = false);
    }
    // } catch (e) {
    //   debugPrint("Error handling QR: $e");

    //   // Ensure camera resumes on any unexpected error
    //   if (controller != null) await controller!.resumeCamera();
    //   setState(() => isScanned = false);
    // }
  }

  void _onQRViewCreated(QRViewController ctrl) {
    controller = ctrl;
    ctrl.scannedDataStream.listen((scanData) async {
      if (!isScanned) {
        setState(() => isScanned = true);

        await controller?.pauseCamera();

        Future.microtask(() {
          _handleScannedToken(scanData.code ?? "");
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determine the size of the square cutout area
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Calculate scan area based on a percentage of the smaller dimension,
    // but cap it at a maximum value (e.g., 350.0) to prevent it from
    // becoming too large on tablets/iPads.
    final maxScanArea = 350.0;
    final proportionalSize =
        (screenWidth < screenHeight ? screenWidth : screenHeight) * 0.9; // 75% of the smallest side

    final scanArea = proportionalSize < maxScanArea ? proportionalSize : maxScanArea;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: AspectRatio(
              aspectRatio: 1.0,
              child: QRView(
                key: qrKey,
                onQRViewCreated: _onQRViewCreated,
                overlay: QrScannerOverlayShape(
                  borderColor: const Color(0xFF00CCCC), // The color of the corner borders
                  borderRadius: 15, // Slightly increased corner radius
                  borderLength: 50, // Significantly increased border length
                  borderWidth: 15, // Significantly increased border thickness
                  cutOutSize: scanArea, // Size of the central cutout area
                  // Changed to white background
                  overlayColor: const Color(0xFFFDF7FE), // Background color outside the cutout area
                ),
              ),
            ),
          ),
          const Expanded(
            flex: 1,
            child: Center(child: Text("QR кодоо камерын хүрээнд байрлуулна уу.")),
          ),
        ],
      ),
    );
  }
}
