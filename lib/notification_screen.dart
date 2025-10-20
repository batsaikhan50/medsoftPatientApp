import 'package:flutter/material.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: const Color(0xFF00CCCC), title: const Text('Мэдэгдэл')),
      body: const Center(child: Text('Мэдэгдэл байхгүй байна')),
    );
  }
}
