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

  // Platform channel for native PiP
  static const _pipChannel = MethodChannel('pip_channel');

  // Getters
  Room? get room => _room;
  bool get micEnabled => _micEnabled;
  bool get camEnabled => _camEnabled;
  bool get isScreenShared => _isScreenShared;
  bool get isConnecting => _isConnecting;
  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessing;
  Participant? get focusedParticipant => _focusedParticipant;
  bool get isConnected => _room != null;
  bool get isOnCallScreen => _isOnCallScreen;

  List<Participant> get allParticipants {
    if (_room == null) return [];
    final local = _room!.localParticipant;
    if (local == null) return [];
    return [local, ..._room!.remoteParticipants.values];
  }

  void init() {
    WidgetsBinding.instance.addObserver(this);
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
      await connect(existingToken: savedToken);
    }
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.microphone].request();
  }

  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('Username');
    if (username == null || username.isEmpty) {
      throw Exception('Хэрэглэгчийн нэр олдсонгүй.');
    }
    final response = await http.get(
      Uri.parse('${Constants.recordingUrl}/token?identity=$username&room=testroom'),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['token'];
    } else {
      debugPrint(response.body.toString());
      throw Exception('Token авахад алдаа гарлаа.');
    }
  }

  Future<void> connect({String? existingToken}) async {
    _isConnecting = true;
    notifyListeners();
    try {
      await _requestPermissions();
      final token = existingToken ?? await _getToken();
      final room = Room(
        roomOptions: const RoomOptions(
          defaultCameraCaptureOptions: CameraCaptureOptions(
            params: VideoParameters(
              dimensions: VideoDimensions(720, 1280),
            ),
          ),
          defaultVideoPublishOptions: VideoPublishOptions(
            simulcast: false,
            videoEncoding: VideoEncoding(
              maxBitrate: 1500 * 1000,
              maxFramerate: 25,
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
            notifyListeners();
          }
        } else {
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

      if (Platform.isIOS) {
        try {
          await _pipChannel.invokeMethod('setupPiP');
          if (room.remoteParticipants.isNotEmpty) {
            await _feedRemoteTrackToNative();
          }
        } catch (_) {}
      }
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
    if (_isScreenShared || _isStartingScreenShare) {
      try {
        await _room?.localParticipant?.setScreenShareEnabled(false);
      } catch (_) {}
      if (Platform.isIOS) {
        try {
          await BroadcastManager().requestStop();
        } catch (_) {}
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
          try {
            await BroadcastManager().requestStop();
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 500));

          try {
            await _pipChannel.invokeMethod('teardownPiP');
          } catch (_) {}
        }

        await Future.delayed(const Duration(milliseconds: 300));

        await _room?.localParticipant?.setScreenShareEnabled(
          true,
          screenShareCaptureOptions: const ScreenShareCaptureOptions(
            useiOSBroadcastExtension: true,
          ),
        );

        if (!Platform.isIOS) {
          _isScreenShared = true;
          _isStartingScreenShare = false;
        }
      } else {
        if (Platform.isIOS) {
          try {
            await BroadcastManager().requestStop();
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 200));
        }

        final participant = _room?.localParticipant;
        await participant?.setScreenShareEnabled(false);
        _isScreenShared = false;

        if (Platform.isIOS) {
          try {
            await _pipChannel.invokeMethod('restorePiP');
          } catch (_) {}
        }

        await Future.delayed(const Duration(milliseconds: 250));
        await participant?.setCameraEnabled(true);
        _camEnabled = true;
      }
    } catch (e) {
      debugPrint("Screen share error: $e");
      _isScreenShared = false;
      _isStartingScreenShare = false;
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
      nav.pushNamed('/call');
    }
  }

  // --- App Lifecycle ---

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_room == null) return;

    if (state == AppLifecycleState.inactive) {
      if (_isStartingScreenShare) return;
      hidePip();
      if (Platform.isAndroid) {
        _enterAndroidPip();
      }
    } else if (state == AppLifecycleState.resumed) {
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
