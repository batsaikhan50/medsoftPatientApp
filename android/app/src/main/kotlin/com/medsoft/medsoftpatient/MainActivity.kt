package com.medsoft.medsoftpatient

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import com.cloudwebrtc.webrtc.GetUserMediaImpl
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun getRenderMode(): RenderMode = RenderMode.texture
    private val PIP_CHANNEL = "pip_channel"
    private val SCREEN_CAPTURE_CHANNEL = "screen_capture_channel"
    private val LOCATION_CHANNEL = "com.medsoft.medsoftpatient/location"
    private var isInCall = false
    private var pipChannel: MethodChannel? = null

    private var pendingScreenShare = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Android 14+: upgradeToMediaProjection() is called synchronously inside
        // GetUserMediaImpl.onReceiveResult, immediately before getMediaProjection().
        // startForeground() is a synchronous Binder call, so AMS has the MEDIA_PROJECTION
        // type recorded before getMediaProjection() executes — no race condition.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            GetUserMediaImpl.onMediaProjectionGranted = Runnable {
                ScreenCaptureService.upgradeToMediaProjection()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CAPTURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForeground" -> {
                        pendingScreenShare = true
                        val intent = Intent(this, ScreenCaptureService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stopForeground" -> {
                        pendingScreenShare = false
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
                    isInCall = true
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !isInPictureInPictureMode) {
                        val params = PictureInPictureParams.Builder()
                            .setAspectRatio(Rational(9, 16))
                            .build()
                        enterPictureInPictureMode(params)
                        result.success(true)
                    } else {
                        result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    }
                }
                "setupPiP" -> {
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
                    "sendXMedsoftTokenToAppDelegate" -> result.success(null)
                    "sendRoomIdToAppDelegate" -> result.success(null)
                    "startLocationManagerAfterLogin" -> {
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
                    "sendLocationToAPIByButton" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (pendingScreenShare) pendingScreenShare = false
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onPictureInPictureModeChanged(isInPip: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPip, newConfig)
        if (isInPip) {
            window.decorView.postInvalidate()
        }
        notifyPipState(isInPip)
    }

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
        if (isInCall && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !isInPictureInPictureMode) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(9, 16))
                .build()
            enterPictureInPictureMode(params)
        }
    }
}
