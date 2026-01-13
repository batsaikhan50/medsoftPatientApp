import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import 'package:medsoft_patient/constants.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PatientCallScreen extends StatefulWidget {
  const PatientCallScreen({super.key});

  @override
  State<PatientCallScreen> createState() => _PatientCallScreenState();
}

class _PatientCallScreenState extends State<PatientCallScreen> {
  Room? _room;
  late CancelListenFunc _listener;
  bool _micEnabled = true;
  bool _camEnabled = true;
  bool _frontCamera = true;
  bool _isConnecting = false; // Add this line

  @override
  void dispose() {
    try {
      _listener();
    } catch (_) {}
    _room?.disconnect();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.microphone].request();
  }

  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();

    // Get saved username
    final username = prefs.getString('Username');

    if (username == null || username.isEmpty) {
      throw Exception('Username not found in SharedPreferences');
    }
    // 1. Use the Token Server URL (Port 3000)
    final response = await http.get(
      Uri.parse('${Constants.liveKitTokenUrl}/token?identity=$username&room=testroom'),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['token'];
    } else {
      throw Exception('Failed to fetch token');
    }
  }

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true; // Start loading
    });
    try {
      await _requestPermissions();
      final token = await _getToken();

      final room = Room();

      // Setup listener to refresh UI when participants join
      _listener = room.events.listen((event) {
        setState(() {});
      });

      // 2. Use the LiveKit Server URL (ws://... port 7880)
      await room.connect(Constants.livekitUrl, token);

      // 3. Enable Local Media
      await room.localParticipant?.setCameraEnabled(true);
      await room.localParticipant?.setMicrophoneEnabled(true);

      setState(() {
        _room = room;
      });

      debugPrint("Doctor connected to room");
    } catch (e) {
      debugPrint('Connection error: $e');
      // Show a snackbar so you know why it failed on the phone
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Connect Error: $e")));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false; // Stop loading regardless of outcome
        });
      }
    }
  }

  // --- UI Helpers ---

  // Separated rendering logic to avoid recursion crashes
  // Update this function in patient_call_screen.dart
  Widget _renderParticipant(Participant participant) {
    // Get the first video track
    final track = participant.videoTrackPublications.firstOrNull?.track;

    if (track == null || track is! VideoTrack) {
      return const Center(child: CircularProgressIndicator());
    }

    return VideoTrackRenderer(
      track,
      fit: VideoViewFit.cover, // Use 'VideoViewFit' (not VideoViewObjectFit)
    );
  }

  Widget _renderParticipantTile(Participant participant) {
    // Find the first video track that is subscribed and not muted
    final trackPub = participant.videoTrackPublications.firstOrNull;
    final isMuted = trackPub?.muted ?? true;

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Video Layer
            if (trackPub?.track is VideoTrack && !isMuted)
              VideoTrackRenderer(trackPub!.track as VideoTrack, fit: VideoViewFit.cover)
            else
              const Center(child: Icon(Icons.videocam_off, color: Colors.white24, size: 40)),

            // Name Tag Overlay
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: Colors.black54,
                child: Text(
                  participant.identity ?? "User",
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return CircleAvatar(
      radius: 28,
      backgroundColor: color,
      child: IconButton(icon: Icon(icon, color: Colors.white), onPressed: onPressed),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Combine all participants into one list for the grid
    List<Participant> allParticipants = [];
    if (_room != null) {
      allParticipants.add(_room!.localParticipant!);
      allParticipants.addAll(_room!.remoteParticipants.values);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Patient video call')),
      body:
          _room == null
              ? Center(
                child:
                    _isConnecting
                        ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 16),
                            Text("Connecting to Room...", style: TextStyle(color: Colors.white)),
                          ],
                        )
                        : ElevatedButton(onPressed: _connect, child: const Text('Join Call')),
              )
              : Column(
                children: [
                  // 1. GRID AREA
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: GridView.builder(
                        itemCount: allParticipants.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              allParticipants.length <= 2
                                  ? 1
                                  : 2, // 1 col for 2 users, 2 cols for 3+
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: allParticipants.length <= 2 ? 1.5 : 1.0,
                        ),
                        itemBuilder: (context, index) {
                          return _renderParticipantTile(allParticipants[index]);
                        },
                      ),
                    ),
                  ),

                  // 2. CONTROLS AREA (Stay at the bottom)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildControlButton(
                          icon: _micEnabled ? Icons.mic : Icons.mic_off,
                          color: _micEnabled ? Colors.white24 : Colors.red,
                          onPressed: () {
                            _micEnabled = !_micEnabled;
                            _room?.localParticipant?.setMicrophoneEnabled(_micEnabled);
                            setState(() {});
                          },
                        ),

                        _buildControlButton(
                          icon: _camEnabled ? Icons.videocam : Icons.videocam_off,
                          color: _camEnabled ? Colors.white24 : Colors.red,
                          onPressed: () {
                            _camEnabled = !_camEnabled;
                            _room?.localParticipant?.setCameraEnabled(_camEnabled);
                            setState(() {});
                          },
                        ),
                        _buildControlButton(
                          icon: Icons.cameraswitch,
                          color: Colors.white24,
                          onPressed: () async {
                            final track =
                                _room?.localParticipant?.videoTrackPublications.firstOrNull?.track;
                            if (track is LocalVideoTrack) {
                              _frontCamera = !_frontCamera;
                              await track.setCameraPosition(
                                _frontCamera ? CameraPosition.front : CameraPosition.back,
                              );
                              setState(() {});
                            }
                          },
                        ),
                        _buildControlButton(
                          icon: Icons.call_end,
                          color: Colors.red,
                          onPressed: () async {
                            await _room?.disconnect();
                            setState(() => _room = null);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
    );
  }
}
