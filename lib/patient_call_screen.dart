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

  Widget _buildVideo(Participant participant) {
    for (final pub in participant.videoTrackPublications) {
      final track = pub.track;
      if (track is VideoTrack) {
        return VideoTrackRenderer(track);
      }
    }
    return const SizedBox();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patient Call')),
      body:
          _room == null
              ? Center(child: ElevatedButton(onPressed: _connect, child: const Text('Join Call')))
              : Column(
                children: [
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 2,
                      children: [
                        _buildVideo(_room!.localParticipant!),
                        ..._room!.remoteParticipants.values.map(_buildVideo),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      await _room?.disconnect();
                      setState(() => _room = null);
                    },
                    child: const Text('Leave Call'),
                  ),
                ],
              ),
    );
  }
}
