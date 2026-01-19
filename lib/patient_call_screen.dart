import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import 'package:medsoft_patient/constants.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

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
  bool _isScreenShared = false;
  bool _isConnecting = false;

  // Track which participant is currently "zoomed"
  Participant? _focusedParticipant;

  @override
  void dispose() {
    try {
      _listener();
    } catch (_) {}
    _room?.disconnect();
    super.dispose();
  }

  // ... (Keep _requestPermissions, _getToken, and _connect exactly as they are)

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

  Widget _renderParticipantTile(Participant participant, {bool isLocal = false}) {
    var trackPub = participant.videoTrackPublications.firstWhereOrNull((e) => e.isScreenShare);
    trackPub ??= participant.videoTrackPublications.firstOrNull;

    final isMuted = isLocal ? !_camEnabled : (trackPub?.muted ?? true);

    return GestureDetector(
      onTap: () {
        setState(() {
          // If already focused, untap to return to grid. Otherwise, focus this one.
          _focusedParticipant = (_focusedParticipant == participant) ? null : participant;
        });
      },
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                trackPub?.isScreenShare == true
                    ? Colors.greenAccent
                    : (isLocal ? Colors.blueAccent : Colors.white10),
            width: 2,
          ),
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
                          fit: trackPub.isScreenShare ? VideoViewFit.contain : VideoViewFit.cover,
                          mirrorMode:
                              (isLocal && !trackPub.isScreenShare)
                                  ? VideoViewMirrorMode.mirror
                                  : VideoViewMirrorMode.off,
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
                    "${participant.identity ?? (isLocal ? "You" : "User")}${trackPub?.isScreenShare == true ? " (Screen)" : ""}",
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
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
        title: const Text('Live Consultation'),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body:
          _room == null
              ? _buildJoinUI()
              : SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child:
                          _focusedParticipant != null
                              ? _buildZoomedView(allParticipants)
                              : _buildDefaultLayout(allParticipants),
                    ),
                    _buildControlBar(),
                  ],
                ),
              ),
    );
  }

  Widget _buildZoomedView(List<Participant> allParticipants) {
    return Column(
      children: [
        // The Big "Zoomed" view
        Expanded(
          flex: 4,
          child: _renderParticipantTile(
            _focusedParticipant!,
            isLocal: _focusedParticipant is LocalParticipant,
          ),
        ),
        // The scrolling list of others at the bottom
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children:
                allParticipants
                    .where((p) => p != _focusedParticipant)
                    .map(
                      (p) => SizedBox(
                        width: 100,
                        child: _renderParticipantTile(p, isLocal: p is LocalParticipant),
                      ),
                    )
                    .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultLayout(List<Participant> allParticipants) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isTablet = MediaQuery.of(context).size.shortestSide >= 600;
        if (allParticipants.length == 2 && !isTablet) {
          return _buildIPhone1vs1(allParticipants);
        }
        return _buildNoScrollGrid(allParticipants, constraints.maxWidth > constraints.maxHeight);
      },
    );
  }

  // ... (Keep _buildJoinUI, _buildIPhone1vs1, _buildNoScrollGrid, _buildControlBar, and _buildActionButton as they are)

  Widget _buildJoinUI() {
    return Center(
      child:
          _isConnecting
              ? const CircularProgressIndicator(color: Colors.white)
              : ElevatedButton(onPressed: _connect, child: const Text('Join Call')),
    );
  }

  Widget _buildIPhone1vs1(List<Participant> participants) {
    return Stack(
      children: [
        Positioned.fill(child: _renderParticipantTile(participants[1])),
        Positioned(
          top: 10,
          right: 10,
          width: 110,
          height: 160,
          child: _renderParticipantTile(participants[0], isLocal: true),
        ),
      ],
    );
  }

  Widget _buildNoScrollGrid(List<Participant> participants, bool isLandscape) {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isLandscape ? 3 : 2,
        childAspectRatio: 1.0,
      ),
      itemCount: participants.length,
      itemBuilder: (context, index) {
        final p = (index == participants.length - 1) ? participants[0] : participants[index + 1];
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
            icon: _isScreenShared ? Icons.stop_screen_share : Icons.screen_share,
            color: _isScreenShared ? Colors.green : Colors.white24,
            onPressed: () async {
              try {
                _isScreenShared = !_isScreenShared;
                await _room?.localParticipant?.setScreenShareEnabled(_isScreenShared);
                setState(() {});
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("Screen Share Error: $e")));
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
