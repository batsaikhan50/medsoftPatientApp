import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // add this import
import 'package:webview_flutter/webview_flutter.dart';

class WebViewScreen extends StatefulWidget {
  final String url;
  final String title;
  final String? roomId; // add roomId
  final String? roomIdNum; // add roomIdNum

  const WebViewScreen({
    super.key,
    required this.url,
    this.title = "Login",
    this.roomId,
    this.roomIdNum,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool arrivedInFifty = false;

  static const platform = MethodChannel('com.example.medsoftpatient/location');
  @override
  void initState() {
    super.initState();

    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadRequest(Uri.parse(widget.url));

    _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (NavigationRequest request) {
          if (request.url.startsWith('medsoftpatient://callback')) {
            Navigator.of(context).pop();
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ),
    );

    // Add method call handler here
    platform.setMethodCallHandler((call) async {
      if (call.method == 'arrivedInFiftyReached') {
        debugPrint("arrivedInFiftyReached received in Dart");

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('arrivedInFifty', true);

        setState(() {
          arrivedInFifty = true;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Та 50 метр дотор ирлээ."),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });

    _loadArrivedInFiftyFlag();
  }

  Future<void> _loadArrivedInFiftyFlag() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      arrivedInFifty = prefs.getBool('arrivedInFifty') ?? false;
    });
  }

  Future<void> _sendLocation() async {
    try {
      await platform.invokeMethod('sendLocationToAPIByButton');

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location sent successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    } on PlatformException catch (e) {
      debugPrint("Failed to send location: '${e.message}'");

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send location: ${e.message}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _markArrived(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('X-Medsoft-Token') ?? '';

      final uri = Uri.parse('https://app.medsoft.care/api/room/arrived?id=$id');

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token', 'X-Medsoft-Token': token},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Амжилттай бүртгэгдлээ'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(json['message'] ?? 'Амжилтгүй'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        final Map<String, dynamic> data = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('HTTP алдаа: ${data.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint("Failed to mark arrived: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Сүлжээний алдаа: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 140,
      height: 40,
      child: ElevatedButton.icon(
        icon: Icon(icon, color: Colors.black),
        label: Text(label, style: const TextStyle(color: Colors.black)),
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF009688),
        title: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.only(
                  left: 12,
                  right: 16,
                  top: 1,
                  bottom: 2,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_back, color: Colors.black),
                    const SizedBox(width: 8),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body:
          widget.title == 'Patient Map'
              ? Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: _buildActionButton(
                      icon: Icons.refresh,
                      label: 'Refresh',
                      onPressed: () {
                        _controller.reload();
                      },
                    ),
                  ),
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _buildActionButton(
                        icon: Icons.send,
                        label: 'Send Location',
                        onPressed: _sendLocation,
                      ),
                    ),
                  ),
                  if (widget.roomIdNum != null && arrivedInFifty)
                    Positioned(
                      bottom: 80,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _buildActionButton(
                          icon: Icons.check_circle,
                          label: 'Arrived',
                          onPressed: () {
                            _markArrived(widget.roomIdNum!);
                          },
                        ),
                      ),
                    ),
                ],
              )
              : WebViewWidget(controller: _controller),
    );
  }
}
