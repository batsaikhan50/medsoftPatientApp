import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<String> _getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('Username') ?? 'Guest';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профайл')),
      body: FutureBuilder<String>(
        future: _getUsername(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Center(
            child: Text(
              'Нэвтэрсэн хэрэглэгч:\n${snapshot.data!}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22),
            ),
          );
        },
      ),
    );
  }
}
