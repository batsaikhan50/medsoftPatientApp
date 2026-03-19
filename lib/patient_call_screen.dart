import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:medsoft_patient/call_manager.dart';
import 'package:collection/collection.dart';

class PatientCallScreen extends StatefulWidget {
  const PatientCallScreen({super.key});

  @override
  State<PatientCallScreen> createState() => _PatientCallScreenState();
}

class _PatientCallScreenState extends State<PatientCallScreen> {
  final _cm = CallManager.instance;

  // --- UI Test Variables ---
  bool uiTest = false;
  int roomSize = 3;

  @override
  void initState() {
    super.initState();
    _cm.setOnCallScreen(true);
    _cm.addListener(_onCallChanged);
    if (!_cm.isConnected) {
      _cm.checkActiveSession();
    }
  }

  @override
  void dispose() {
    _cm.removeListener(_onCallChanged);
    _cm.setOnCallScreen(false);

    // Show PiP if still connected
    if (_cm.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _cm.showPip();
      });
    }

    // Reset orientations to default when leaving the call
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _onCallChanged() {
    if (mounted) setState(() {});
  }

  Widget _renderParticipantTile(Participant participant, {bool isLocal = false}) {
    var trackPub = participant.videoTrackPublications.firstWhereOrNull((e) => e.isScreenShare);
    trackPub ??= participant.videoTrackPublications.firstOrNull;

    final isMuted = isLocal ? !_cm.camEnabled : (trackPub?.muted ?? true);

    // Wrap remote tiles in KeyedSubtree so only the remote VideoTrackRenderer
    // (decoder) is rebuilt on EGL transitions. Rebuilding the local tile would
    // restart the VP8 encoder (OMX.Exynos.VP8.Encoder Executing→Idle) causing
    // a blank feed from the new ImageTextureEntry during encoder reinit.
    final tile = GestureDetector(
      onTap: () {
        _cm.setFocusedParticipant(_cm.focusedParticipant == participant ? null : participant);
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
                          fit: VideoViewFit.contain,
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
                    "${participant.identity.isEmpty ? (isLocal ? 'Та' : 'Хэрэглэгч') : participant.identity}${trackPub?.isScreenShare == true ? ' (Дэлгэц)' : ''}",
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (isLocal) return tile;
    return KeyedSubtree(
      key: ValueKey('${participant.identity}_${_cm.videoRebuildToken}'),
      child: tile,
    );
  }

  Widget _buildDummyTile(int index) {
    return GestureDetector(
      onTap: () => setState(() => uiTest = false),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10, width: 2),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bug_report, color: Colors.white24, size: 40),
              Text("Mock User $index", style: const TextStyle(color: Colors.white24)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double shortestSide = MediaQuery.of(context).size.shortestSide;
    final bool isTablet = shortestSide >= 600;

    if (!isTablet) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    // Never filter participants based on PiP state — removing participants from
    // the list disposes VideoTrackRenderers during the EGL transition, which
    // creates new ImageTextureEntry objects in a broken EGL context (white screen).
    // Local tile visibility in PiP is handled inside _buildIPhone1vs1 instead.
    final allParticipants = _cm.allParticipants;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar:
          _cm.isInAndroidPip
              ? null
              : AppBar(
                title: Text(uiTest ? 'UI TEST MODE ($roomSize)' : 'Patient Portal'),
                backgroundColor: Colors.black,
                iconTheme: const IconThemeData(color: Colors.white),
                titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18),
              ),
      body:
          (_cm.room == null && !uiTest)
              ? _buildInitialUI()
              : SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child:
                          _cm.focusedParticipant != null
                              ? _buildZoomedView(allParticipants)
                              : _buildDefaultLayout(allParticipants),
                    ),
                    if (!_cm.isInAndroidPip) _buildControlBar(),
                  ],
                ),
              ),
    );
  }

  Widget _buildInitialUI() {
    return Center(
      child:
          _cm.isConnecting
              ? const CircularProgressIndicator(color: Colors.white)
              : ElevatedButton(
                onPressed: () async {
                  try {
                    await _cm.connect();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text("Connect Error: $e")));
                    }
                  }
                },
                child: const Text('Start Consultation'),
              ),
    );
  }

  Widget _buildZoomedView(List<Participant> allParticipants) {
    return Column(
      children: [
        Expanded(
          flex: 4,
          child: _renderParticipantTile(
            _cm.focusedParticipant!,
            isLocal: _cm.focusedParticipant is LocalParticipant,
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 120),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children:
                allParticipants
                    .where((p) => p != _cm.focusedParticipant)
                    .map(
                      (p) => SizedBox(
                        width: 120,
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
        int effectiveCount = uiTest ? roomSize : allParticipants.length;
        bool isLandscape = constraints.maxWidth > constraints.maxHeight;

        if (uiTest) {
          return GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isLandscape ? 3 : 2,
              childAspectRatio: 1.0,
            ),
            itemCount: roomSize,
            itemBuilder: (context, index) => _buildDummyTile(index),
          );
        }

        if (effectiveCount == 2 && (MediaQuery.of(context).size.shortestSide < 600)) {
          return _buildIPhone1vs1(allParticipants);
        }

        return _buildNoScrollGrid(allParticipants, isLandscape);
      },
    );
  }

  Widget _buildIPhone1vs1(List<Participant> participants) {
    return Stack(
      children: [
        Positioned.fill(child: _renderParticipantTile(participants[1])),
        // Use Visibility(maintainState: true) so the local VideoTrackRenderer
        // is NEVER disposed during PiP transitions — disposing during the EGL
        // surface recreation creates a new ImageTextureEntry in a broken
        // context, causing a white screen on the 2nd+ PiP cycle.
        Positioned(
          top: 10,
          right: 10,
          width: 110,
          height: 160,
          child: Visibility(
            visible: !_cm.isInAndroidPip,
            maintainState: true,
            child: _renderParticipantTile(participants[0], isLocal: true),
          ),
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
        final p = participants[index];
        return _renderParticipantTile(p, isLocal: index == 0);
      },
    );
  }

  Widget _buildControlBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionButton(
              icon: _cm.micEnabled ? Icons.mic : Icons.mic_off,
              color: _cm.micEnabled ? Colors.white24 : Colors.red,
              onPressed: _cm.toggleMic,
            ),
            _buildActionButton(
              icon: _cm.camEnabled ? Icons.videocam : Icons.videocam_off,
              color: _cm.camEnabled ? Colors.white24 : Colors.red,
              onPressed: _cm.toggleCam,
            ),
            _buildActionButton(
              icon: Icons.flip_camera_ios,
              color: Colors.white24,
              onPressed: _cm.flipCamera,
            ),
            _buildActionButton(
              icon: _cm.isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
              color: _cm.isRecording ? Colors.red : Colors.white24,
              onPressed: _cm.toggleRecording,
            ),
            _buildActionButton(
              icon: _cm.isScreenShared ? Icons.stop_screen_share : Icons.screen_share,
              color: _cm.isScreenShared ? Colors.green : Colors.white24,
              onPressed: _cm.toggleScreenShare,
            ),
            _buildActionButton(
              icon: Icons.call_end,
              color: Colors.red,
              onPressed: () async {
                await _cm.disconnect();
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
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
