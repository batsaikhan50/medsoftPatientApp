package com.medsoft.medsoftpatient

import android.Manifest
import android.app.AlertDialog
import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Rational
import android.view.LayoutInflater
import android.view.WindowManager
import android.widget.Button
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
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
    private var pendingServiceAction: String? = null

    private var pendingScreenShare = false

    companion object {
        private const val LOCATION_PERMISSION_REQUEST_CODE = 1
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 2
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun onResume() {
        super.onResume()
        checkNotificationPermissionAndPromptIfNeeded()
    }

    private fun getNotificationPermissionStatus(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            when (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)) {
                PackageManager.PERMISSION_GRANTED -> 2
                else -> -1
            }
        } else {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (notificationManager.areNotificationsEnabled()) 2 else -1
        }
    }

    private fun checkNotificationPermissionAndPromptIfNeeded() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isLoggedIn = prefs.getBoolean("flutter.isLoggedIn", false)
        if (!isLoggedIn) return

        if (getNotificationPermissionStatus() == -1) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_REQUEST_CODE
                )
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                        handlePermissionAndStartService(result)
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

    private fun checkLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun isBackgroundLocationGranted(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return ContextCompat.checkSelfPermission(
                this, Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    private fun handlePermissionAndStartService(result: MethodChannel.Result) {
        if (checkLocationPermission()) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !isBackgroundLocationGranted()) {
                showBackgroundLocationDialog()
            } else {
                startLocationService()
            }
            result.success(null)
            return
        }

        pendingServiceAction = "start"
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
            LOCATION_PERMISSION_REQUEST_CODE
        )
        result.success(null)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !isBackgroundLocationGranted()) {
                    showBackgroundLocationDialog()
                } else {
                    startLocationService()
                }
            }
            pendingServiceAction = null
        } else if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            // nothing extra needed
        }
    }

    private fun showBackgroundLocationDialog() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val view = LayoutInflater.from(this).inflate(R.layout.dialog_location_permission, null)
            val dialog = AlertDialog.Builder(this)
                .setView(view)
                .setCancelable(false)
                .create()
            dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)

            view.findViewById<Button>(R.id.btn_open_settings).setOnClickListener {
                startActivity(Intent().apply {
                    action = Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                    data = Uri.fromParts("package", packageName, null)
                })
                startLocationService()
                dialog.dismiss()
            }
            view.findViewById<Button>(R.id.btn_continue).setOnClickListener {
                startLocationService()
                dialog.dismiss()
            }
            dialog.show()
            dialog.window?.setLayout(
                (resources.displayMetrics.widthPixels * 0.92).toInt(),
                WindowManager.LayoutParams.WRAP_CONTENT
            )
        } else {
            startLocationService()
        }
    }

    private fun startLocationService() {
        val intent = Intent(this, LocationService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(this, intent)
        } else {
            startService(intent)
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
