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
  bool _isConnecting = false;

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
    final username = prefs.getString('Username');
    if (username == null || username.isEmpty) {
      throw Exception('Username not found in SharedPreferences');
    }
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
    setState(() => _isConnecting = true);
    try {
      await _requestPermissions();
      final token = await _getToken();
      final room = Room();
      _listener = room.events.listen((event) => setState(() {}));
      await room.connect(Constants.livekitUrl, token);
      await room.localParticipant?.setCameraEnabled(true);
      await room.localParticipant?.setMicrophoneEnabled(true);
      setState(() => _room = room);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Connect Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  // --- UI Helpers (Mirrored from Doctor Screen) ---

  Widget _renderParticipantTile(Participant participant, {bool isLocal = false}) {
    final trackPub = participant.videoTrackPublications.firstOrNull;
    final isMuted = isLocal ? !_camEnabled : (trackPub?.muted ?? true);

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isLocal ? Colors.blueAccent : Colors.white10, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned.fill(
              child:
                  (trackPub?.track is VideoTrack && !isMuted)
                      ? VideoTrackRenderer(
                        trackPub!.track as VideoTrack,
                        fit: VideoViewFit.cover,
                        mirrorMode: isLocal ? VideoViewMirrorMode.mirror : VideoViewMirrorMode.off,
                      )
                      : Container(
                        color: Colors.blueGrey.withOpacity(0.1),
                        child: const Center(
                          child: Icon(Icons.person, color: Colors.white24, size: 50),
                        ),
                      ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  participant.identity ?? (isLocal ? "You" : "User"),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Participant> allParticipants = [];
    if (_room != null) {
      allParticipants = [_room!.localParticipant!, ..._room!.remoteParticipants.values];
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Live Call'),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18),
      ),
      body:
          _room == null
              ? Center(
                child:
                    _isConnecting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : ElevatedButton(onPressed: _connect, child: const Text('Join Call')),
              )
              : SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          bool isTablet = MediaQuery.of(context).size.shortestSide >= 600;
                          bool isLandscape = constraints.maxWidth > constraints.maxHeight;

                          if (allParticipants.length == 2 && !isTablet) {
                            return _buildIPhone1vs1(allParticipants);
                          }
                          return _buildNoScrollGrid(allParticipants, isTablet, isLandscape);
                        },
                      ),
                    ),
                    _buildControlBar(),
                  ],
                ),
              ),
    );
  }

  Widget _buildIPhone1vs1(List<Participant> participants) {
    return Stack(
      children: [
        Positioned.fill(child: _renderParticipantTile(participants[1])), // Remote
        Positioned(
          top: 10,
          right: 10,
          width: 110,
          height: 160,
          child: _renderParticipantTile(participants[0], isLocal: true), // Local
        ),
      ],
    );
  }

  Widget _buildNoScrollGrid(List<Participant> participants, bool isTablet, bool isLandscape) {
    int count = participants.length;
    final local = participants[0];
    final remotes = participants.sublist(1);

    if (isTablet && count == 2) {
      return Flex(
        direction: isLandscape ? Axis.horizontal : Axis.vertical,
        children: [
          Expanded(child: _renderParticipantTile(remotes[0])),
          Expanded(child: _renderParticipantTile(local, isLocal: true)),
        ],
      );
    }

    if (count == 3) {
      Axis dir = (isTablet && isLandscape) ? Axis.horizontal : Axis.vertical;
      return Flex(
        direction: dir,
        children: [
          Expanded(child: _renderParticipantTile(remotes[0])),
          Expanded(child: _renderParticipantTile(remotes[1])),
          Expanded(child: _renderParticipantTile(local, isLocal: true)),
        ],
      );
    }

    if (count >= 4 && count <= 6) {
      List<Widget> rows = [];
      int rowCount = count == 4 ? 2 : 3;
      for (int i = 0; i < rowCount; i++) {
        List<Widget> rowChildren = [];
        if (i == 0) {
          rowChildren = [
            Expanded(child: _renderParticipantTile(remotes[0])),
            Expanded(child: _renderParticipantTile(remotes[1])),
          ];
        } else if (i == 1) {
          rowChildren =
              count == 4
                  ? [
                    Expanded(child: _renderParticipantTile(remotes[2])),
                    Expanded(child: _renderParticipantTile(local, isLocal: true)),
                  ]
                  : [
                    Expanded(child: _renderParticipantTile(remotes[2])),
                    Expanded(child: _renderParticipantTile(remotes[3])),
                  ];
        } else {
          rowChildren =
              count == 5
                  ? [Expanded(child: _renderParticipantTile(local, isLocal: true))]
                  : [
                    Expanded(child: _renderParticipantTile(remotes[4])),
                    Expanded(child: _renderParticipantTile(local, isLocal: true)),
                  ];
        }
        rows.add(Expanded(child: Row(children: rowChildren)));
      }
      return Column(children: rows);
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.0,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        final p = (index == count - 1) ? participants[0] : participants[index + 1];
        return _renderParticipantTile(p, isLocal: p == participants[0]);
      },
    );
  }

  Widget _buildControlBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            icon: _micEnabled ? Icons.mic : Icons.mic_off,
            color: _micEnabled ? Colors.white24 : Colors.red,
            onPressed: () {
              _micEnabled = !_micEnabled;
              _room?.localParticipant?.setMicrophoneEnabled(_micEnabled);
              setState(() {});
            },
          ),
          _buildActionButton(
            icon: _camEnabled ? Icons.videocam : Icons.videocam_off,
            color: _camEnabled ? Colors.white24 : Colors.red,
            onPressed: () {
              _camEnabled = !_camEnabled;
              _room?.localParticipant?.setCameraEnabled(_camEnabled);
              setState(() {});
            },
          ),
          _buildActionButton(
            icon: Icons.cameraswitch,
            color: Colors.white24,
            onPressed: () async {
              final track = _room?.localParticipant?.videoTrackPublications.firstOrNull?.track;
              if (track is LocalVideoTrack) {
                _frontCamera = !_frontCamera;
                await track.setCameraPosition(
                  _frontCamera ? CameraPosition.front : CameraPosition.back,
                );
                setState(() {});
              }
            },
          ),
          _buildActionButton(
            icon: Icons.call_end,
            color: Colors.red,
            onPressed: () async {
              await _room?.disconnect();
              setState(() => _room = null);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
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
}
