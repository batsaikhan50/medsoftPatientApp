import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import 'package:medsoft_patient/constants.dart';
import 'package:permission_handler/permission_handler.dart';

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
    final response = await http.get(
      Uri.parse('${Constants.liveKitTokenUrl}/token?identity=patient1&room=testroom'),
    );
    final data = jsonDecode(response.body);
    return data['token'];
  }

  Future<void> _connect() async {
    try {
      await _requestPermissions();
      final token = await _getToken();
      final room = Room();

      // ... listener setup ...

      // USE IT HERE:
      await room.connect(Constants.livekitUrl, token); // <--- Use the constant here

      await room.localParticipant?.setCameraEnabled(true);
      await room.localParticipant?.setMicrophoneEnabled(true);

      setState(() {
        _room = room;
      });
    } catch (e) {
      debugPrint('Connection error: $e');
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Patient Call')),
      body:
          _room == null
              ? Center(child: ElevatedButton(onPressed: _connect, child: const Text('Join Call')))
              : Stack(
                children: [
                  // 1. FULL SCREEN: Remote Participant (The Doctor)
                  // Change the remote participant check to this:
                  Positioned.fill(
                    child:
                        _room!.remoteParticipants.isNotEmpty
                            ? _renderParticipant(
                              _room!.remoteParticipants.values.first,
                            ) // Should be the doctor
                            : const Center(
                              child: Text(
                                "Waiting for Doctor...",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                  ),
                  // 2. OVERLAY: Local Preview (The Patient)
                  // Inside your build method's Stack:
                  Positioned(
                    top: 16,
                    right: 16,
                    width: 110,
                    height: 150,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white24,
                          width: 2,
                        ), // Added width for visibility
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        // REMOVED ', mirror: _frontCamera' below
                        child: _renderParticipant(_room!.localParticipant!),
                      ),
                    ),
                  ),

                  // 3. BOTTOM CONTROLS
                  Positioned(
                    bottom: 30,
                    left: 0,
                    right: 0,
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
