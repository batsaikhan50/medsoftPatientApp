import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
// ignore: implementation_imports
import 'package:livekit_client/src/managers/broadcast_manager.dart';
import 'package:medsoft_patient/constants.dart';
import 'package:medsoft_patient/pip_overlay.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

class CallManager extends ChangeNotifier with WidgetsBindingObserver {
  CallManager._();
  static final CallManager instance = CallManager._();

  // Navigator key for PiP tap-to-return navigation
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // LiveKit state
  Room? _room;
  CancelListenFunc? _listener;
  bool _micEnabled = true;
  bool _camEnabled = true;
  bool _isScreenShared = false;
  bool _isConnecting = false;
  bool _isRecording = false;
  bool _isProcessing = false;
  Participant? _focusedParticipant;

  // PiP overlay
  OverlayEntry? _pipOverlay;
  bool _isOnCallScreen = false;
  bool _isInAndroidPip = false;

  // Incremented after a PiP transition so VideoTrackRenderers are rebuilt
  // once the EGL surface and MediaCodec have fully settled (Android issue).
  int _videoRebuildToken = 0;
  int get videoRebuildToken => _videoRebuildToken;

  // Room ID for create/join modes
  String? _roomId;
  String? get roomId => _roomId;

  // Platform channel for native PiP
  static const _pipChannel = MethodChannel('pip_channel');
  static const _screenCaptureChannel = MethodChannel('screen_capture_channel');

  // Getters
  Room? get room => _room;
  bool get micEnabled => _room?.localParticipant?.isMicrophoneEnabled() ?? _micEnabled;
  bool get camEnabled => _room?.localParticipant?.isCameraEnabled() ?? _camEnabled;
  bool get isScreenShared => _isScreenShared;
  bool get isConnecting => _isConnecting;
  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessing;
  Participant? get focusedParticipant => _focusedParticipant;
  bool get isConnected => _room != null;
  bool get isOnCallScreen => _isOnCallScreen;
  bool get isInAndroidPip => _isInAndroidPip;

  List<Participant> get allParticipants {
    if (_room == null) return [];
    final local = _room!.localParticipant;
    if (local == null) return [];
    return [local, ..._room!.remoteParticipants.values];
  }

  void init() {
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) {
      _pipChannel.setMethodCallHandler(_handleNativePipCall);
    }
  }

  Future<dynamic> _handleNativePipCall(MethodCall call) async {
    if (call.method == 'pipModeChanged') {
      final bool isInPip = call.arguments as bool;
      _isInAndroidPip = isInPip;
      notifyListeners();
    }
  }

  void setOnCallScreen(bool value) {
    _isOnCallScreen = value;
    if (value) {
      hidePip();
    }
  }

  void setFocusedParticipant(Participant? participant) {
    _focusedParticipant = participant;
    notifyListeners();
  }

  Future<void> checkActiveSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('active_call_token');
    if (savedToken != null && _room == null) {
      debugPrint("Found active session, reconnecting...");
      try {
        await connect(existingToken: savedToken);
      } catch (e) {
        // Token is expired or invalid — connect() already cleared it.
        debugPrint("Saved session reconnect failed: $e");
      }
    }
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.microphone].request();
  }

  Future<String> _getToken({String? roomId}) async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('Username');
    if (username == null || username.isEmpty) {
      throw Exception('Username not found in SharedPreferences');
    }
    final effectiveRoomId = roomId ?? 'testroom';
    final response = await http.get(
      Uri.parse('${Constants.recordingUrl}/token?identity=$username&room=$effectiveRoomId'),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['token'];
    } else {
      debugPrint(response.body.toString());
      throw Exception('Failed to fetch token');
    }
  }

  String _generateRoomId() {
    final random = DateTime.now().millisecondsSinceEpoch % 900000 + 100000;
    return random.toString();
  }

  Future<void> connect({String? existingToken, String? roomId}) async {
    _isConnecting = true;
    // Generate room ID if not provided (create mode)
    _roomId = roomId ?? _generateRoomId();
    notifyListeners();
    try {
      await _requestPermissions();
      final token = existingToken ?? await _getToken(roomId: _roomId);
      final room = Room(
        roomOptions: const RoomOptions(
          defaultCameraCaptureOptions: CameraCaptureOptions(
            params: VideoParameters(
              dimensions: VideoDimensions(720, 1280), // 720p portrait
              // dimensions: VideoDimensions(540, 960),     // 540p portrait
              // dimensions: VideoDimensions(360, 640),  // 360p portrait
            ),
          ),
          defaultVideoPublishOptions: VideoPublishOptions(
            simulcast: false, // disable multi-layer encoding
            // H264 instead of VP8: Samsung Exynos has dedicated H264 hardware
            // (OMX.Exynos.avc.dec) vs the buggy VP8 hybrid decoder
            // (OMX.Exynos.vp8.dec ERROR 0x8000100b) that causes white PiP on Note 10.
            videoCodec: 'h264',
            videoEncoding: VideoEncoding(
              maxBitrate: 1500 * 1000, // 1.5 Mbps
              // maxBitrate: 800 * 1000, // 800 Kbps
              // maxBitrate: 500 * 1000,  // 500 Kbps
              maxFramerate: 25,
              // maxFramerate: 15,
            ),
          ),
          defaultScreenShareCaptureOptions: ScreenShareCaptureOptions(
            useiOSBroadcastExtension: true,
          ),
        ),
      );

      _listener = room.events.listen((event) {
        if (event is RoomRecordingStatusChanged) {
          _isRecording = event.activeRecording;
          notifyListeners();
        }
        if (event is LocalTrackPublishedEvent) {
          if (event.publication.isScreenShare) {
            _isScreenShared = true;
            _isStartingScreenShare = false;
            _camEnabled = false;
            debugPrint("Screen share track published");
            // Restore PiP now that screen share is established.
            // ReplayKit is done initializing, so PiP won't conflict.
            // This allows out-of-app PiP during active screen sharing.
            if (Platform.isIOS) {
              _pipChannel.invokeMethod('restorePiP').catchError((_) {});
            }
            notifyListeners();
          }
        } else if (event is LocalTrackUnpublishedEvent) {
          if (event.publication.isScreenShare && !_isStartingScreenShare) {
            _isScreenShared = false;
            _camEnabled = true;
            debugPrint("Screen share track unpublished");
            // Don't call restorePiP here — toggleScreenShare() handles it.
            // Calling it from both places causes double-restore → EXC_BAD_ACCESS.
            notifyListeners();
          }
        } else {
          // When a remote participant publishes a video track,
          // feed it to native PiP layer so frames are ready before PiP starts.
          if (Platform.isIOS && (event is TrackSubscribedEvent)) {
            _feedRemoteTrackToNative();
          }
          notifyListeners();
        }
      });

      await room.connect(Constants.livekitUrl, token);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_call_token', token);

      _isRecording = room.isRecording;
      _room = room;

      await room.localParticipant?.setCameraEnabled(_camEnabled);
      await room.localParticipant?.setMicrophoneEnabled(_micEnabled);

      // Setup native PiP.
      // iOS: initialises AVPictureInPictureController and feeds remote track.
      // Android: sets isInCall=true on native side so onUserLeaveHint can
      //          enter PiP on the very first Home-press (before any lifecycle
      //          inactive event fires from Flutter).
      try {
        await _pipChannel.invokeMethod('setupPiP');
        if (Platform.isIOS && room.remoteParticipants.isNotEmpty) {
          await _feedRemoteTrackToNative();
        }
      } catch (_) {}
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_call_token');
      rethrow;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    // Stop screen share broadcast before disconnecting to prevent
    // "interrupted by another application" error on next session.
    if (_isScreenShared || _isStartingScreenShare) {
      try {
        await _room?.localParticipant?.setScreenShareEnabled(false);
      } catch (_) {}
      // Signal the broadcast extension process to stop (removes red status bar)
      if (Platform.isIOS) {
        try {
          await BroadcastManager().requestStop();
        } catch (_) {}
      }
      if (Platform.isAndroid) {
        // Stop the foreground service and give MediaProjection/MediaCodec time
        // to release native resources before room.disconnect() tears down WebRTC.
        // Without this delay the MediaCodec encoder is freed while still active → native crash.
        try {
          await _screenCaptureChannel.invokeMethod('stopForeground');
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    _isStartingScreenShare = false;
    await _room?.disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_call_token');
    _listener?.call();
    _listener = null;
    _room = null;
    _micEnabled = true;
    _camEnabled = true;
    _isScreenShared = false;
    _isRecording = false;
    _focusedParticipant = null;
    _roomId = null;
    hidePip();
    try {
      await _pipChannel.invokeMethod('dispose');
    } catch (_) {}
    notifyListeners();
  }

  void toggleMic() {
    _micEnabled = !_micEnabled;
    _room?.localParticipant?.setMicrophoneEnabled(_micEnabled);
    notifyListeners();
  }

  void toggleCam() {
    _camEnabled = !_camEnabled;
    _room?.localParticipant?.setCameraEnabled(_camEnabled);
    notifyListeners();
  }

  Future<void> flipCamera() async {
    final track = _room?.localParticipant?.videoTrackPublications.firstOrNull?.track;
    if (track is LocalVideoTrack) {
      final settings = track.mediaStreamTrack.getSettings();
      final isFront = settings['facingMode'] == 'user';
      await track.restartTrack(
        CameraCaptureOptions(cameraPosition: isFront ? CameraPosition.back : CameraPosition.front),
      );
      notifyListeners();
    }
  }

  Future<void> toggleRecording() async {
    if (_isProcessing) return;
    _isProcessing = true;
    notifyListeners();

    final bool starting = !_isRecording;
    final endpoint = starting ? 'start-recording' : 'stop-recording';
    final url = Uri.parse('${Constants.recordingUrl}/$endpoint?room=testroom');

    try {
      final response = await http.post(url);
      if (response.statusCode == 200) {
        _isRecording = starting;
        final data = utf8.encode(starting ? 'rec_on' : 'rec_off');
        await _room?.localParticipant?.publishData(data);
      }
    } catch (e) {
      debugPrint("Recording Toggle Error: $e");
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  bool _isStartingScreenShare = false;

  Future<void> toggleScreenShare() async {
    try {
      final bool willStartSharing = !_isScreenShared;
      if (willStartSharing) {
        _isStartingScreenShare = true;
        notifyListeners();

        await _room?.localParticipant?.setCameraEnabled(false);
        _camEnabled = false;

        if (Platform.isIOS) {
          // Stop any lingering broadcast from a previous attempt to prevent
          // the "Recording interrupted by another application" error popup.
          try {
            await BroadcastManager().requestStop();
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 500));

          // Tear down PiP controller to avoid AVPictureInPictureController
          // conflicting with ReplayKit's broadcast extension.
          try {
            await _pipChannel.invokeMethod('teardownPiP');
          } catch (_) {}
        }

        await Future.delayed(const Duration(milliseconds: 300));

        if (Platform.isAndroid) {
          await _screenCaptureChannel.invokeMethod('startForeground');
          await Future.delayed(const Duration(milliseconds: 200));
        }

        // On iOS with broadcast extension, this shows the picker and returns
        // null immediately. The actual track publish happens later via
        // LocalTrackPublishedEvent when the Darwin notification arrives.
        await _room?.localParticipant?.setScreenShareEnabled(
          true,
          screenShareCaptureOptions: const ScreenShareCaptureOptions(
            useiOSBroadcastExtension: true,
          ),
        );

        // On non-iOS platforms, setScreenShareEnabled awaits the track publish,
        // so we can set the state here. On iOS, LocalTrackPublishedEvent will
        // set _isScreenShared = true when the broadcast actually starts.
        if (!Platform.isIOS) {
          _isScreenShared = true;
          _isStartingScreenShare = false;
        }
      } else {
        // Signal the broadcast extension to stop first (removes red status bar)
        if (Platform.isIOS) {
          try {
            await BroadcastManager().requestStop();
          } catch (_) {}
          // Give the extension time to finish
          await Future.delayed(const Duration(milliseconds: 200));
        }

        final participant = _room?.localParticipant;
        await participant?.setScreenShareEnabled(false);
        _isScreenShared = false;

        if (Platform.isAndroid) {
          _screenCaptureChannel.invokeMethod('stopForeground').catchError((_) {});
        }

        // Restore PiP controller on iOS
        if (Platform.isIOS) {
          try {
            await _pipChannel.invokeMethod('restorePiP');
          } catch (_) {}
        }

        await Future.delayed(const Duration(milliseconds: 250));
        await participant?.setCameraEnabled(true);
        _camEnabled = true;

        // On Android the camera track is torn down and republished during
        // screen share, leaving ImageTextureEntry stale. Wait for the new
        // camera track to start producing frames, then rebuild renderers so
        // the next PiP cycle doesn't encounter a stale surface.
        if (Platform.isAndroid) {
          await Future.delayed(const Duration(milliseconds: 300));
          _videoRebuildToken++;
        }
      }
    } catch (e) {
      debugPrint("Screen share error: $e");
      _isScreenShared = false;
      _isStartingScreenShare = false;
      if (Platform.isAndroid) {
        _screenCaptureChannel.invokeMethod('stopForeground').catchError((_) {});
      }
      // Restore PiP if screen share failed
      if (Platform.isIOS) {
        try {
          await _pipChannel.invokeMethod('restorePiP');
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  // --- PiP Overlay Management ---

  void showPip([BuildContext? context]) {
    if (_room == null || _pipOverlay != null) return;

    // Get the Navigator's own overlay via its state.
    final navState = navigatorKey.currentState;
    if (navState == null) return;
    final overlay = navState.overlay;
    if (overlay == null) return;

    _pipOverlay = OverlayEntry(
      builder: (context) =>
          PipOverlayWidget(callManager: this, onTap: _returnToCallScreen, onClose: hidePip),
    );
    overlay.insert(_pipOverlay!);
  }

  void hidePip() {
    _pipOverlay?.remove();
    _pipOverlay = null;
  }

  void _returnToCallScreen() {
    hidePip();
    final nav = navigatorKey.currentState;
    if (nav != null) {
      // Use a lazy import to avoid circular dependency
      nav.pushNamed('/call');
    }
  }

  // --- App Lifecycle ---

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_room == null) return;

    if (state == AppLifecycleState.inactive) {
      // Don't trigger PiP when the broadcast picker is showing
      if (_isStartingScreenShare) return;
      // Hide in-app PiP overlay before going to background
      hidePip();
      if (Platform.isAndroid) {
        // _isInAndroidPip state is managed by onPictureInPictureModeChanged
        // via _handleNativePipCall. Just trigger the enter here.
        _enterAndroidPip();
      }
      // iOS PiP is handled natively by AppDelegate.willResignActive
    } else if (state == AppLifecycleState.resumed) {
      // Backup for the race condition where resumed is processed by Dart
      // BEFORE pipModeChanged(false) arrives (ordering depends on Android
      if (Platform.isAndroid && _isInAndroidPip) {
        _isInAndroidPip = false;
        notifyListeners();
      }
      // Re-show in-app PiP if not on call screen
      if (!_isOnCallScreen && _room != null && _pipOverlay == null) {
        showPip();
      }
    }
  }

  Future<void> _enterAndroidPip() async {
    if (_room == null || !Platform.isAndroid) return;
    try {
      await _pipChannel.invokeMethod('enterPiP');
    } catch (e) {
      debugPrint("Android PiP error: $e");
    }
  }

  /// Feed remote video track ID to native side (for iOS PiP).
  /// Called when a remote participant subscribes to a track.
  Future<void> _feedRemoteTrackToNative() async {
    if (!Platform.isIOS || _room == null) return;
    try {
      final remoteParticipant = _room!.remoteParticipants.values.firstOrNull;
      final remotePub =
          remoteParticipant?.videoTrackPublications.firstWhereOrNull((e) => !e.isScreenShare) ??
          remoteParticipant?.videoTrackPublications.firstOrNull;
      if (remotePub?.track != null) {
        final trackId = remotePub!.track!.mediaStreamTrack.id;
        await _pipChannel.invokeMethod('remoteStream', {'remoteId': trackId});
      }
    } catch (e) {
      debugPrint("Feed remote track error: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    hidePip();
    _listener?.call();
    super.dispose();
  }
}
