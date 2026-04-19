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

  // --- Join Mode Variables ---
  String? _mode; // 'join'
  String _joinRoomId = '';
  String _joinError = '';

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

    final isMuted = trackPub?.muted ?? true;

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
                    "${isLocal ? "Та" : participant.identity}${trackPub?.isScreenShare == true ? " (Дэлгэц)" : ""}",
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
                title: Text(uiTest ? 'UI TEST MODE ($roomSize)' : 'Иргэний портал'),
                backgroundColor: Colors.black,
                iconTheme: const IconThemeData(color: Colors.white),
                titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18),
              ),
      body:
          (_cm.room == null && !uiTest)
              ? _buildInitialUI()
              : SafeArea(
                child: Stack(
                  children: [
                    Column(
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
                    // Room ID Display Overlay
                    if (_cm.roomId != null && !_cm.isInAndroidPip)
                      Positioned(
                        top: 20,
                        left: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF5865F2).withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Өрөө: ',
                                style: TextStyle(color: Colors.white, fontSize: 16),
                              ),
                              Text(
                                _cm.roomId!,
                                style: const TextStyle(
                                  color: Color(0xFF5865F2),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
    );
  }

  Widget _buildInitialUI() {
    // Show loading while connecting
    if (_cm.isConnecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Холбогдож байна...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    // Show join screen after join button is tapped
    if (_mode == 'join') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1F22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF333333)),
                ),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'JOIN VIDEO CALL',
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '6 оронтой нууц дугаар оруулна уу',
                      style: TextStyle(fontSize: 14, color: Color(0xFFDBDEE1)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (val) {
                        setState(() {
                          _joinRoomId = val;
                          _joinError = '';
                        });
                      },
                      style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 4),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: '000000',
                        hintStyle: const TextStyle(color: Color(0xFF999999)),
                        filled: true,
                        fillColor: const Color(0xFF2C2F33),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF5865F2), width: 2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF5865F2), width: 2),
                        ),
                        counterText: '',
                      ),
                    ),
                    if (_joinError.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(_joinError, style: const TextStyle(color: Color(0xFFDA373C))),
                      ),
                    if (_joinRoomId.length == 6) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              _joinRoomId.length == 6
                                  ? () async {
                                    try {
                                      await _cm.connect(roomId: _joinRoomId);
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text("Нэгдэхэд алдаа гарлаа: $e")),
                                        );
                                      }
                                    }
                                  }
                                  : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _joinRoomId.length == 6
                                    ? const Color(0xFF5865F2)
                                    : const Color(0xFF666666),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Орох'),
                        ),
                      ),
                    ],
                  ],
                ),
                ),
              ),
              Positioned(
                top: -16,
                right: -16,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _mode = null;
                      _joinRoomId = '';
                      _joinError = '';
                    });
                  },
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: Color(0xFF333333),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white70, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show main menu with Join button only (no Create for patient)
    return Center(
      child: ElevatedButton(
        onPressed: () {
          setState(() {
            _mode = 'join';
            _joinRoomId = '';
            _joinError = '';
          });
        },
        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[700]),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_call, size: 20, color: Colors.white),
            SizedBox(width: 8),
            Text('JOIN', style: TextStyle(color: Colors.white)),
          ],
        ),
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
