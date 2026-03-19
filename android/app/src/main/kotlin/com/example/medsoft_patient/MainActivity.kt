package com.example.medsoft_patient

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // TextureView instead of SurfaceView: Samsung One UI has a known bug where
    // SurfaceView surfaces are not redrawn after the PiP window is created,
    // causing the entire PiP window to show white. TextureView uses Android's
    // hardware-accelerated layer compositing which handles PiP correctly on One UI.
    override fun getRenderMode(): RenderMode = RenderMode.texture
    private val PIP_CHANNEL = "pip_channel"
    private val SCREEN_CAPTURE_CHANNEL = "screen_capture_channel"
    private val LOCATION_CHANNEL = "com.example.medsoft_patient/location"
    private var isInCall = false
    private var pipChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CAPTURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForeground" -> {
                        val intent = Intent(this, ScreenCaptureService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stopForeground" -> {
                        stopService(Intent(this, ScreenCaptureService::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipChannel!!.setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPiP" -> {
                        // setAutoEnterEnabled is intentionally NOT used. Auto-enter races with
                        // Flutter's AppLifecycleState.inactive → _enterAndroidPip() path, causing
                        // a double-trigger on the 2nd+ PiP cycle: both auto-enter animation and
                        // manual enterPictureInPictureMode fire while isInPictureInPictureMode is
                        // still false → Samsung compositor gets corrupted → white window.
                        // Using manual-only entry via onUserLeaveHint (all Android O+) is clean
                        // and consistent with no double-trigger risk.
                        isInCall = true
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !isInPictureInPictureMode) {
                            try {
                                val params = PictureInPictureParams.Builder()
                                    .setAspectRatio(Rational(9, 16))
                                    .build()
                                enterPictureInPictureMode(params)
                                result.success(true)
                            } catch (e: IllegalStateException) {
                                result.error("PIP_ERROR", "Failed to enter PiP: ${e.message}", null)
                            }
                        } else {
                            result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        }
                    }
                    "setupPiP" -> {
                        // Arm isInCall so onUserLeaveHint enters PiP on first press.
                        // No setAutoEnterEnabled — see enterPiP comment above.
                        isInCall = true
                        result.success(true)
                    }
                    "dispose" -> {
                        isInCall = false
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendXMedsoftTokenToAppDelegate" -> {
                        val args = call.arguments as? Map<*, *>
                        val xMedsoftToken = args?.get("xMedsoftToken") as? String
                        // Handle token storage or processing here
                        result.success(null)
                    }
                    "sendRoomIdToAppDelegate" -> {
                        val args = call.arguments as? Map<*, *>
                        val roomId = args?.get("roomId") as? String
                        // Handle room ID processing here
                        result.success(null)
                    }
                    "startLocationManagerAfterLogin" -> {
                        // Start location services
                        val intent = Intent(this, LocationService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "stopLocationUpdates" -> {
                        stopService(Intent(this, LocationService::class.java))
                        result.success(null)
                    }
                    "sendLocationToAPIByButton" -> {
                        // Handle location sending
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onPictureInPictureModeChanged(isInPip: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPip, newConfig)
        if (isInPip) {
            // Force the compositor to redraw the view hierarchy into the PiP surface.
            // On Samsung One UI, the TextureView hardware layer can be stale on the
            // 2nd+ PiP cycle. postInvalidate() queues a redraw from the UI thread.
            window.decorView.postInvalidate()
        }
        notifyPipState(isInPip)
    }

    // Samsung One UI (Note 10, S-series) may not reliably fire
    // onPictureInPictureModeChanged. onMultiWindowModeChanged fires for ALL
    // multi-window changes and isInPictureInPictureMode gives the exact state.
    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean, newConfig: Configuration) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notifyPipState(isInPictureInPictureMode)
        }
    }

    private fun notifyPipState(isInPip: Boolean) {
        pipChannel?.invokeMethod("pipModeChanged", isInPip)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Manual PiP entry for ALL Android O+ versions (including Android 12+).
        // Previously Android 12+ relied on setAutoEnterEnabled, but that races with
        // Flutter's manual enterPiP call → double-trigger → white PiP on 2nd cycle.
        if (isInCall && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !isInPictureInPictureMode) {
            try {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(9, 16))
                    .build()
                enterPictureInPictureMode(params)
            } catch (e: IllegalStateException) {
                // Activity doesn't support PiP (e.g., not declared in manifest)
                // or PiP is not available for some reason. Log and continue.
                android.util.Log.e("MainActivity", "Failed to enter PiP: ${e.message}")
            }
        }
    }
}
