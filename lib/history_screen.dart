import 'package:flutter/material.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const Center(
        child: Text(
          'HISTORY SCREEN',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      ),
    );
  }
}