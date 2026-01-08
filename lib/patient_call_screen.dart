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
  void initState() {
    super.initState();
    // Nothing needed here; connect called from button
  }

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
      Uri.parse('${Constants.rtcUrl}/token?identity=patient1&room=testroom'),
    );

    final data = jsonDecode(response.body);
    return data['token'];
  }

  Future<void> _connect() async {
    debugPrint('Connecting to LiveKit server...');
    await _requestPermissions();

    // 1️⃣ Get token
    final token = await _getToken();
    debugPrint('Received nodeJS token: $token');
    // 2️⃣ Create room
    final room = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));

    // 3️⃣ Listen to all room events

    _listener = room.events.listen((event) {
      if (event is ParticipantEvent) {
        setState(() {}); // update UI when participants join/leave
      }
    });

    // 4️⃣ Connect to LiveKit server
    await room.connect('ws://100.100.10.100:7880', token);

    // 5️⃣ Enable camera and mic
    await room.localParticipant?.setCameraEnabled(true);
    await room.localParticipant?.setMicrophoneEnabled(true);

    setState(() {
      _room = room;
    });
  }

  Future<void> _toggleMic() async {
    _micEnabled = !_micEnabled;
    await _room?.localParticipant?.setMicrophoneEnabled(_micEnabled);
    setState(() {});
  }

  Future<void> _toggleCamera() async {
    _camEnabled = !_camEnabled;
    await _room?.localParticipant?.setCameraEnabled(_camEnabled);
    setState(() {}); // This triggers the build method to refresh the _buildVideo widget
  }

  Future<void> _switchCamera() async {
    // 1. Get the track publication for the camera
    final trackPub = _room?.localParticipant?.videoTrackPublications.firstOrNull;
    final track = trackPub?.track;

    // 2. Check if it's a LocalVideoTrack and call setCameraPosition there
    if (track is LocalVideoTrack) {
      _frontCamera = !_frontCamera;
      await track.setCameraPosition(_frontCamera ? CameraPosition.front : CameraPosition.back);
      setState(() {});
    }
  }

  Widget _buildVideo(Participant participant, {bool mirror = false}) {
    // Check if this is the local participant and if camera is disabled
    bool isMuted = false;
    if (participant is LocalParticipant) {
      isMuted = !_camEnabled;
    } else {
      // For remote participants, check if their video track is muted
      isMuted = participant.videoTrackPublications.any((pub) => pub.muted);
    }

    // Find the video track
    VideoTrack? videoTrack;
    for (final pub in participant.videoTrackPublications) {
      if (pub.track is VideoTrack) {
        videoTrack = pub.track as VideoTrack;
        break;
      }
    }

    return Stack(
      children: [
        // 1. The Video Track (only show if not muted)
        if (videoTrack != null && !isMuted)
          VideoTrackRenderer(
            videoTrack,
            mirrorMode: mirror ? VideoViewMirrorMode.mirror : VideoViewMirrorMode.off,
          )
        else
          // 2. The "Camera Hidden" Placeholder
          Container(
            color: Colors.grey[800],
            child: const Center(
              child: Text(
                'Camera Hidden',
                style: TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patient Call')),
      body:
          _room == null
              ? Center(child: ElevatedButton(onPressed: _connect, child: const Text('Join Call')))
              : Stack(
                children: [
                  // 🔹 Remote video (full screen)
                  if (_room!.remoteParticipants.isNotEmpty)
                    _buildVideo(_room!.remoteParticipants.values.first)
                  else
                    _buildVideo(_room!.localParticipant!),

                  // 🔹 Local preview (top-right)
                  Positioned(
                    top: 16,
                    right: 16,
                    width: 120,
                    height: 160,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildVideo(_room!.localParticipant!, mirror: _frontCamera),
                    ),
                  ),

                  // 🔹 Bottom control bar
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          iconSize: 32,
                          color: Colors.white,
                          icon: Icon(_micEnabled ? Icons.mic : Icons.mic_off),
                          onPressed: _toggleMic,
                        ),
                        IconButton(
                          iconSize: 32,
                          color: Colors.white,
                          icon: Icon(_camEnabled ? Icons.videocam : Icons.videocam_off),
                          onPressed: _toggleCamera,
                        ),
                        IconButton(
                          iconSize: 32,
                          color: Colors.white,
                          icon: const Icon(Icons.cameraswitch),
                          onPressed: _switchCamera,
                        ),
                        IconButton(
                          iconSize: 32,
                          color: Colors.red,
                          icon: const Icon(Icons.call_end),
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
