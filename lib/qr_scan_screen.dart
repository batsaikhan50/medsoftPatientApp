import 'dart:io';

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
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      controller!.pauseCamera();
    }
    controller!.resumeCamera();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shortestSide = MediaQuery.of(context).size.shortestSide;
      debugPrint('shortestSide : $shortestSide');

      const double tabletBreakpoint = 600;

      if (shortestSide < tabletBreakpoint) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    });
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    controller?.dispose();
    super.dispose();
  }

  Future<void> _handleScannedToken(String url) async {
    Uri uri = Uri.parse(url);
    String? token;
    if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == "qr") {
      token = uri.pathSegments[1];
    }

    if (token == null) {
      debugPrint("Invalid QR format");

      if (controller != null) await controller!.resumeCamera();
      setState(() => isScanned = false);
      return;
    }

    debugPrint("Extracted token: $token");

    final response = await _authDAO.waitQR(token);

    if (response.statusCode == 200) {
      debugPrint("Wait API success: ${response.statusCode}");

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => ClaimQRScreen(token: token!)),
      );
    } else {
      debugPrint("Wait API failed: ${response.statusCode}");

      final errorMessage = "Error: Status Code ${response.message}";

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage), backgroundColor: Colors.red));
      }

      if (controller != null) {
        await controller!.resumeCamera();
        debugPrint("Camera resumed after API failure.");
      }

      setState(() => isScanned = false);
    }
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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final maxScanArea = 350.0;
    final proportionalSize = (screenWidth < screenHeight ? screenWidth : screenHeight) * 0.9;

    final scanArea = proportionalSize < maxScanArea ? proportionalSize : maxScanArea;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // Set centerTitle to false to align the title (your button) to the left
        centerTitle: false,
        automaticallyImplyLeading: false, // Hides default back arrow
        backgroundColor: Colors.transparent, // Transparent to show camera behind
        elevation: 0,
        title: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Row(
            mainAxisSize: MainAxisSize.min, // Wraps content so it doesn't stretch
            children: [
              Container(
                // Using the specific padding and style you requested
                padding: const EdgeInsets.only(left: 12, right: 16, top: 6, bottom: 6),
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.all(Radius.circular(25)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.arrow_back, color: Colors.black, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "Буцах",
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,

            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
              overlay: QrScannerOverlayShape(
                borderColor: const Color(0xFF00CCCC),
                borderRadius: 15,
                borderLength: 50,
                borderWidth: 15,
                cutOutSize: scanArea,

                overlayColor: const Color(0xFFFDF7FE),
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
