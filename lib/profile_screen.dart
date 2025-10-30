import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:medsoft_patient/api/auth_dao.dart';
import 'package:medsoft_patient/webview_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onGuideTap;
  final VoidCallback onLogoutTap;

  const ProfileScreen({super.key, required this.onGuideTap, required this.onLogoutTap});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // **Change 2: Create State class**
  final _authDao = AuthDAO();
  final String danAuthUrl = 'https://app.medsoft.care/api/dan/auth';

  // **Change 3: Hold the future in the state**
  late Future<Map<String, dynamic>> _initialDataFuture;

  @override
  void initState() {
    super.initState();
    // Initialize the future when the widget is created
    _initialDataFuture = _loadInitialData();
  }

  Future<Map<String, dynamic>> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();

    // Default local data (used if DAN call fails or is not complete)
    String firstName = prefs.getString('Firstname') ?? '';
    String lastName = prefs.getString('Lastname') ?? '';
    String phoneNumber = prefs.getString('Username') ?? 'Утасны дугааргүй';
    String regNo = prefs.getString('RegNo') ?? 'РД байхгүй';

    // NEW FIELDS with defaults
    String civilId = 'ИБД байхгүй';
    String passportAddress = 'Хаяг байхгүй';
    String birthday = 'Төрсөн огноо байхгүй';
    String gender = 'Хүйс байхгүй';
    String? base64Image;

    bool isDanAuthenticated = false;

    try {
      final danResponse = await _authDao.getPatientInfo();

      if (danResponse.statusCode == 200 && danResponse.data != null) {
        final danData = danResponse.data ?? {};

        isDanAuthenticated = danData['dan'] ?? false;

        // Update user-facing fields with data from DAN
        if (isDanAuthenticated) {
          regNo = danData['regNo'] ?? regNo;
          firstName = danData['firstname'] ?? firstName;
          lastName = danData['lastname'] ?? lastName;
          phoneNumber = danData['phone'] ?? phoneNumber;

          // NEW FIELD EXTRACTION
          civilId = danData['civilId'] ?? civilId;
          passportAddress = danData['passportAddress'] ?? passportAddress;
          birthday = danData['birthday']?.split(' ')[0] ?? birthday; // Use only the date part

          // Map gender to Mongolian
          final rawGender = danData['gender'] as String? ?? 'Хүйс байхгүй';
          gender =
              rawGender == 'Эрэгтэй' ? 'Эрэгтэй' : (rawGender == 'Эмэгтэй' ? 'Эмэгтэй' : rawGender);

          base64Image = danData['image'];

          // Optional: Update SharedPreferences with new data if needed
          await prefs.setString('RegNo', regNo);
          await prefs.setString('Firstname', firstName);
          await prefs.setString('Lastname', lastName);
          // ... save other fields as needed
        }
      } else {
        print('Error checking DAN status: ${danResponse.message}');
      }
    } catch (e) {
      print('Exception during DAN info download: $e');
    }

    return {
      'firstName': firstName,
      'lastName': lastName,
      'phoneNumber': phoneNumber,
      'regNo': regNo,
      'danAuthenticated': isDanAuthenticated,
      // NEW DATA TO RETURN
      'civilId': civilId,
      'passportAddress': passportAddress,
      'birthday': birthday,
      'gender': gender,
      'base64Image': base64Image,
    };
  }

  // Helper function to generate initials
  String _getInitials(String firstName, String lastName) {
    String firstInitial = firstName.isNotEmpty ? firstName[0] : '';
    String lastInitial = lastName.isNotEmpty ? lastName[0] : '';
    return (lastInitial + firstInitial).toUpperCase();
  }

  static const Color _wateryGreen = Color.fromARGB(255, 67, 180, 100);
  static const Color _dangerRed = Color.fromARGB(255, 217, 83, 96);
  // Helper function to decode Base64 image
  Widget _buildProfileImage(String? base64Image, String initials) {
    if (base64Image != null && base64Image.isNotEmpty) {
      try {
        final parts = base64Image.split(',');
        final imageBytes = base64Decode(parts.last);

        return Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.blueAccent.withOpacity(0.8), width: 2),
          ),
          child: ClipOval(
            child: Image.memory(
              imageBytes,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _initialsAvatar(initials);
              },
            ),
          ),
        );
      } catch (e) {
        print("Error decoding image: $e");
        return _initialsAvatar(initials);
      }
    }
    return _initialsAvatar(initials);
  }

  // Helper for the initials avatar fallback
  Widget _initialsAvatar(String initials) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.8), shape: BoxShape.circle),
      child: Center(
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    Widget icon,
    String text, {
    String? subtitle,
    bool isMultiline = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(
        crossAxisAlignment: isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: <Widget>[
          Padding(padding: const EdgeInsets.only(right: 15.0), child: icon),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null)
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: isMultiline ? 14 : 16,
                    fontWeight: isMultiline ? FontWeight.normal : FontWeight.w500,
                    color: isMultiline ? Colors.black87 : Colors.black,
                  ),
                  maxLines: isMultiline ? 3 : 1,
                  overflow: isMultiline ? TextOverflow.ellipsis : TextOverflow.clip,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Conditional onPressed logic (Updated to use async/await and setState)
  void danButtonOnPressed(BuildContext context) async {
    if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (ctx) => WebViewScreen(url: danAuthUrl, title: 'ДАН нэвтрэх')),
      );

      // Re-run the data loading logic after returning from the WebView.
      setState(() {
        _initialDataFuture = _loadInitialData();
      });
    }
  }

  // Helper for 'РД' and 'ИБД' custom icons - FIX 2 APPLIED HERE
  Widget _buildCustomIcon(String text, Color color) {
    return Container(
      // Increased width slightly to prevent 'ИБД' wrapping
      width: 35,
      height: 30,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _initialDataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 50.0),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final data = snapshot.data ?? {};
            final String firstName = data['firstName'] ?? '';
            final String lastName = data['lastName'] ?? '';
            final String phoneNumber = data['phoneNumber'] ?? 'Алдаа';
            final String regNo = data['regNo'] ?? 'Алдаа';
            final bool danAuthenticated = data['danAuthenticated'] ?? false;

            // NEW DATA EXTRACTION
            final String civilId = data['civilId'] ?? 'Алдаа';
            final String passportAddress = data['passportAddress'] ?? 'Алдаа';
            final String birthday = data['birthday'] ?? 'Алдаа';
            final String gender = data['gender'] ?? 'Алдаа';
            final String? base64Image = data['base64Image'];

            final String initials = _getInitials(firstName, lastName);
            final String fullName = '${lastName.isNotEmpty ? lastName[0] : ''}.$firstName';

            // --- INFO ROWS LIST ---
            List<Widget> infoRows = [
              // 1st Row: Registration Number (RegNo)
              _buildInfoRow(
                context,
                _buildCustomIcon('РД', Colors.blueGrey),
                regNo,
                subtitle: 'Регистрийн дугаар',
              ),
              const Divider(height: 20, thickness: 1),

              // 2. NEW Row: Civil ID - ONLY IF AUTHENTICATED (FIX 1)
              if (danAuthenticated) ...[
                _buildInfoRow(
                  context,
                  _buildCustomIcon('ИБД', Colors.orange),
                  civilId,
                  subtitle: 'Иргэний бүртгэлийн дугаар',
                ),
                const Divider(height: 20, thickness: 1),
              ],

              // 3rd Row: Phone Number
              _buildInfoRow(
                context,
                const Icon(Icons.phone, color: Colors.green),
                phoneNumber,
                subtitle: 'Утасны дугаар',
              ),
              const Divider(height: 20, thickness: 1),

              // 4. NEW Row: Passport Address - ONLY IF AUTHENTICATED (FIX 1)
              if (danAuthenticated) ...[
                _buildInfoRow(
                  context,
                  const Icon(Icons.location_on, color: Colors.red),
                  passportAddress,
                  subtitle: 'Оршин суугаа хаяг',
                  isMultiline: true,
                ),
                const Divider(height: 20, thickness: 1),
              ],

              // 5. NEW Row: Birthday
              _buildInfoRow(
                context,
                const Icon(Icons.cake, color: Colors.pink),
                birthday,
                subtitle: 'Төрсөн огноо',
              ),
              const Divider(height: 20, thickness: 1),

              // 6. NEW Row: Gender
              _buildInfoRow(
                context,
                Icon(
                  gender == 'Эрэгтэй'
                      ? Icons.male
                      : (gender == 'Эмэгтэй' ? Icons.female : Icons.person),
                  color:
                      gender == 'Эрэгтэй'
                          ? Colors.blue
                          : (gender == 'Эмэгтэй' ? Colors.pink : Colors.grey),
                ),
                gender,
                subtitle: 'Хүйс',
              ),
              const Divider(height: 20, thickness: 1),

              // Last Row: Information Note
              _buildInfoRow(
                context,
                Icon(
                  danAuthenticated ? Icons.check_circle : Icons.cloud_download,
                  color: danAuthenticated ? _wateryGreen : _dangerRed,
                ),
                danAuthenticated
                    ? 'Таны мэдээлэл ДАН системээр баталгаажсан байна.'
                    : 'ДАН системээс мэдээллээ дуудан цаг авах болон бусад үйлчилгээг авах боломжтой',
                isMultiline: true,
              ),
            ];

            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 20),
                  // PROFILE PICTURE & Name
                  Center(
                    child: Column(
                      children: [
                        _buildProfileImage(base64Image, initials),
                        const SizedBox(height: 20),
                        Center(
                          child: Text(
                            fullName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),

                  // --- USER INFO CONTAINER ---
                  Container(
                    padding: const EdgeInsets.all(15.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    // Use the conditional list of widgets here
                    child: Column(children: infoRows),
                  ),

                  // DAN Button - FIX 3 APPLIED HERE
                  Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: ElevatedButton(
                      onPressed: () => danButtonOnPressed(context),
                      style: ElevatedButton.styleFrom(
                        // Use the new watery green color
                        backgroundColor: danAuthenticated ? _wateryGreen : Colors.white,
                        foregroundColor: danAuthenticated ? Colors.white : Colors.black,
                        elevation: 1.0,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        side: BorderSide(
                          color: danAuthenticated ? _wateryGreen : _dangerRed,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        // Removed mainAxisSize: MainAxisSize.min
                        children: <Widget>[
                          Image.asset('assets/icon/dan.png', height: 24),
                          const SizedBox(width: 8),

                          // FIX: Wrap the Text widget in Expanded to prevent overflow
                          Expanded(
                            child: Text(
                              danAuthenticated ? '-с дахин мэдээлэл дуудах' : '-с мэдээлэл дуудах',
                              style: TextStyle(
                                fontSize: danAuthenticated ? 14.6 : 18,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign:
                                  TextAlign
                                      .left, // Ensure text starts from the left of its expanded box
                              overflow: TextOverflow.fade, // Handle extreme cases with a fade
                              softWrap: false, // Ensure it stays on one line
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // The Spacer is removed since SingleChildScrollView should not contain Spacer
                  // Instead, we use SizedBox for spacing
                  const SizedBox(height: 20),

                  // "Хэрэглэх заавар" (Guide) Button
                  ListTile(
                    leading: const Icon(Icons.info_outline, color: Colors.blueAccent),
                    title: const Text('Хэрэглэх заавар', style: TextStyle(fontSize: 18)),
                    onTap: widget.onGuideTap,
                  ),
                  const Divider(),

                  // "Гарах" (Logout) Button
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    child: Material(
                      elevation: 1.0,
                      color: _dangerRed, // Use consistent color
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        onTap: widget.onLogoutTap,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: const Text(
                            'Гарах',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
