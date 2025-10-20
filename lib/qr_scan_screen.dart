import 'dart:developer';

import 'package:flutter/material.dart';
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
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> _handleScannedToken(String url) async {
    try {
      Uri uri = Uri.parse(url);
      String? token;
      if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == "qr") {
        token = uri.pathSegments[1];
      }

      if (token == null) {
        log("Invalid QR format");
        return;
      }

      log("Extracted token: $token");

      final response = await _authDAO.waitQR(token);

      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => ClaimQRScreen(token: token!)),
        );
      } else {
        log("Wait API failed: ${response.statusCode}");
      }
    } catch (e) {
      log("Error handling QR: $e");
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
    return Scaffold(
      body: Column(
        children: [
          Expanded(flex: 5, child: QRView(key: qrKey, onQRViewCreated: _onQRViewCreated)),
          const Expanded(
            flex: 1,
            child: Center(child: Text("QR кодоо камерын хүрээнд байрлуулна уу.")),
          ),
        ],
      ),
    );
  }
}
