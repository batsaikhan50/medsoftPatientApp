import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:medsoft_patient/call_manager.dart';
import 'package:collection/collection.dart';

class PipOverlayWidget extends StatefulWidget {
  final CallManager callManager;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const PipOverlayWidget({
    super.key,
    required this.callManager,
    required this.onTap,
    required this.onClose,
  });

  @override
  State<PipOverlayWidget> createState() => _PipOverlayWidgetState();
}

class _PipOverlayWidgetState extends State<PipOverlayWidget>
    with SingleTickerProviderStateMixin {
  double _xPos = 0;
  double _yPos = 100;

  static const double _width = 120;
  static const double _height = 170;
  static const double _tabWidth = 28;
  static const double _tabHeight = 52;
  static const double _snapPadding = 8.0;

  bool _isHidden = false;
  bool _snappedToLeft = false;
  bool _isSnappedToEdge = false;

  late AnimationController _animController;
  Animation<double>? _currentAnimation;

  @override
  void initState() {
    super.initState();
    widget.callManager.addListener(_onCallStateChanged);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = MediaQuery.of(context).size;
      setState(() {
        _snappedToLeft = false;
        _isSnappedToEdge = true;
        _xPos = size.width - _width - _snapPadding;
        _yPos = size.height - _height - 120;
      });
    });
  }

  @override
  void dispose() {
    widget.callManager.removeListener(_onCallStateChanged);
    _currentAnimation?.removeListener(_onAnimTick);
    _animController.dispose();
    super.dispose();
  }

  void _onCallStateChanged() {
    if (!widget.callManager.isConnected) {
      widget.onClose();
      return;
    }
    if (mounted) setState(() {});
  }

  void _snapToNearestEdge() {
    final size = MediaQuery.of(context).size;
    final centerX = _xPos + _width / 2;
    _snappedToLeft = centerX < size.width / 2;

    final targetX = _snappedToLeft
        ? _snapPadding
        : size.width - _width - _snapPadding;

    setState(() {
      _isSnappedToEdge = true;
      _isHidden = false;
    });
    _animateX(targetX);
  }

  void _toggleHide() {
    final size = MediaQuery.of(context).size;
    final newHidden = !_isHidden;

    final double targetX;
    if (newHidden) {
      targetX = _snappedToLeft ? -_width : size.width;
    } else {
      targetX = _snappedToLeft ? _snapPadding : size.width - _width - _snapPadding;
    }

    setState(() => _isHidden = newHidden);
    _animateX(targetX);
  }

  void _animateX(double targetX) {
    _currentAnimation?.removeListener(_onAnimTick);
    final startX = _xPos;
    final anim = Tween<double>(begin: startX, end: targetX).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _currentAnimation = anim;
    anim.addListener(_onAnimTick);
    _animController.forward(from: 0);
  }

  void _onAnimTick() {
    if (mounted && _currentAnimation != null) {
      setState(() => _xPos = _currentAnimation!.value);
    }
  }

  Widget _buildVideoContent() {
    final room = widget.callManager.room;
    if (room == null) return _buildPlaceholder();

    final remoteParticipant = room.remoteParticipants.values.firstOrNull;
    if (remoteParticipant == null) return _buildPlaceholder();

    final trackPub = remoteParticipant.videoTrackPublications.firstWhereOrNull(
          (e) => !e.isScreenShare,
        ) ??
        remoteParticipant.videoTrackPublications.firstOrNull;

    if (trackPub?.track is VideoTrack && !(trackPub?.muted ?? true)) {
      return VideoTrackRenderer(
        trackPub!.track as VideoTrack,
        fit: VideoViewFit.cover,
        mirrorMode: VideoViewMirrorMode.off,
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: const Center(
        child: Icon(Icons.videocam, color: Colors.white38, size: 32),
      ),
    );
  }

  Widget _buildPullTab() {
    final IconData icon;
    if (_snappedToLeft) {
      icon = _isHidden ? Icons.chevron_right : Icons.chevron_left;
    } else {
      icon = _isHidden ? Icons.chevron_left : Icons.chevron_right;
    }

    return GestureDetector(
      onTap: _toggleHide,
      child: Container(
        width: _tabWidth,
        height: _tabHeight,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: _snappedToLeft
              ? const BorderRadius.only(
                  topRight: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                )
              : const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.callManager.isConnected) return const SizedBox.shrink();

    return Positioned(
      left: _xPos,
      top: _yPos,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main PiP window
          GestureDetector(
            onPanUpdate: _isHidden
                ? null
                : (details) {
                    setState(() {
                      _xPos += details.delta.dx;
                      _yPos += details.delta.dy;
                      final size = MediaQuery.of(context).size;
                      _xPos = _xPos.clamp(0, size.width - _width);
                      _yPos = _yPos.clamp(0, size.height - _height);
                      _isSnappedToEdge = false;
                    });
                  },
            onPanEnd: _isHidden ? null : (_) => _snapToNearestEdge(),
            onTap: _isHidden ? null : widget.onTap,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              shadowColor: Colors.black54,
              child: Container(
                width: _width,
                height: _height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24, width: 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Positioned.fill(child: _buildVideoContent()),
                      if (!_isHidden) ...[
                        // Close button
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: widget.onClose,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                        // Expand icon
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.open_in_full,
                                color: Colors.white, size: 12),
                          ),
                        ),
                      ],
                      // Recording indicator
                      if (widget.callManager.isRecording)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Pull-tab
          if (_isSnappedToEdge)
            Positioned(
              left: _snappedToLeft ? _width : -_tabWidth,
              top: (_height - _tabHeight) / 2,
              child: _buildPullTab(),
            ),
        ],
      ),
    );
  }
}
