package com.example.medsoft_patient

import android.Manifest
import android.app.AlertDialog
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.location.Location
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings // NEW IMPORT
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationServices
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.medsoft_patient/location"
    private lateinit var channel: MethodChannel
    private lateinit var sharedPreferences: SharedPreferences
    private lateinit var fusedLocationClient: FusedLocationProviderClient

    private var xMedsoftToken: String? = null
    private var currentRoomId: String? = null

    private val locationServiceReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val method = intent?.getStringExtra("method")
            when (method) {
                "arrivedInFiftyReached" -> {
                    val arrivedInFifty = intent.getBooleanExtra("value_bool", false)
                    CoroutineScope(Dispatchers.Main).launch {
                        channel.invokeMethod("arrivedInFiftyReached", mapOf("arrivedInFifty" to arrivedInFifty))
                    }
                }
                "navigateToLogin" -> {
                    CoroutineScope(Dispatchers.Main).launch {
                        channel.invokeMethod("navigateToLogin", null)
                    }
                }
            }
        }
    }

    companion object {
        private const val LOCATION_PERMISSION_REQUEST_CODE = 1001
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter("com.example.medsoft_patient.FLUTTER_COMMUNICATION")
        ContextCompat.registerReceiver(this, locationServiceReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
    }

    override fun onDestroy() {
        unregisterReceiver(locationServiceReceiver)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLastLocation" -> getLastLocation(result)
                "sendLocationToAPIByButton" -> sendLocationToAPIByButton(result)
                "startLocationManagerAfterLogin" -> {
                    Log.d("MainActivity", "Invoked startLocationManagerAfterLogin")
                    startLocationManagerAfterLogin()
                    result.success(null)
                }
                "sendXMedsoftTokenToAppDelegate" -> {
                    val args = call.arguments as? Map<*, *>
                    xMedsoftToken = args?.get("xMedsoftToken") as? String
                    Log.d("MainActivity", "Received xMedsoftToken: $xMedsoftToken")
                    result.success(null)
                }
                "stopLocationUpdates" -> {
                    stopLocationUpdates()
                    result.success(null)
                }
                "sendRoomIdToAppDelegate" -> {
                    val args = call.arguments as? Map<*, *>
                    currentRoomId = args?.get("roomId") as? String
                    Log.d("MainActivity", "Received roomId: $currentRoomId")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        sharedPreferences = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
    }

    private fun checkLocationPermission(): Boolean {
        // Checks only for ACCESS_FINE_LOCATION (Foreground Location)
        return (ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED)
    }

    private fun isBackgroundLocationGranted(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    // NEW: Dialog for when permission is permanently denied (Don't Ask Again)
    private fun showInitialPermissionDeniedDialog() {
        val builder = AlertDialog.Builder(this)
        builder.setTitle("Байршил тогтоох зөвшөөрөл шаардлагатай")
        builder.setMessage(
            "Энэ функцийг ашиглахад байршил тогтоох хандалт зайлшгүй шаардлагатай. Та өмнө нь энэ зөвшөөрлийг цуцалсан байна. Тохиргоо руу орж апп-д байршлын хандалтыг гараар идэвхжүүлнэ үү."
        )
        builder.setPositiveButton("Тохиргоо нээх") { _, _ ->
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            val uri = Uri.fromParts("package", packageName, null)
            intent.data = uri
            startActivity(intent)
        }
        builder.setNegativeButton("Цуцлах") { dialog, _ ->
            dialog.dismiss()
            Log.e("MainActivity", "Initial location permission permanently denied by user.")
        }
        builder.create().show()
    }

    // Dialog to guide the user to the Settings screen to grant "Allow all the time"
    private fun showBackgroundLocationDialog() {
        val builder = AlertDialog.Builder(this)
        builder.setTitle("Байршил тогтоох зөвшөөрөл шаардлагатай")
        builder.setMessage(
            "Апп хаалттай байх үед байршлыг үнэн зөв тогтоохын тулд 'Үргэлж зөвшөөрөх' хандалт шаардлагатай. Тохиргоо руу орж зөвшөөрлийг 'Зөвхөн апп-ыг ашиглах үед' гэснээс 'Үргэлж зөвшөөрөх' болгож өөрчилнө үү."
        )
        builder.setPositiveButton("Тохиргоо нээх") { _, _ ->
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            val uri = Uri.fromParts("package", packageName, null)
            intent.data = uri
            startActivity(intent)
        }
        builder.setNegativeButton("Цуцлах") { dialog, _ ->
            dialog.dismiss()
            Log.e("MainActivity", "Background location permission denied by user. Service started, but will be limited by OS.")
            // Start the service with limited permission (Foreground only)
            startLocationService()
        }
        builder.create().show()
    }

    private fun checkBackgroundLocationPermissionAndStartService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !isBackgroundLocationGranted()) {
            // Android Q+ and Background Location is NOT granted, show the guide dialog
            showBackgroundLocationDialog()
        } else {
            // Older Android version or permission is granted
            startLocationService()
        }
    }


    private fun getLastLocation(result: MethodChannel.Result) {
        if (!checkLocationPermission()) {
            result.error("LOCATION_PERMISSION_DENIED", "Location permission is not granted.", null)
            return
        }

        fusedLocationClient.lastLocation.addOnSuccessListener { location: Location? ->
            if (location != null) {
                val locationData = mapOf(
                    "latitude" to location.latitude,
                    "longitude" to location.longitude
                )
                result.success(locationData)
            } else {
                result.error("LOCATION_ERROR", "Location not available", null)
            }
        }.addOnFailureListener { e ->
            result.error("LOCATION_ERROR", "Failed to get location: ${e.message}", null)
        }
    }

    private fun sendLocationToAPIByButton(result: MethodChannel.Result) {
        if (!checkLocationPermission()) {
            result.error("LOCATION_PERMISSION_DENIED", "Location permission is not granted.", null)
            return
        }

        fusedLocationClient.lastLocation.addOnSuccessListener { location: Location? ->
            if (location != null) {
                sendLocationToAPI(location)
                Log.d("MainActivity", "Button sent success")
                result.success(null)
            } else {
                result.error("LOCATION_ERROR", "Location not available for button action", null)
            }
        }.addOnFailureListener { e ->
            result.error("LOCATION_ERROR", "Failed to get location for button: ${e.message}", null)
        }
    }

    private fun startLocationManagerAfterLogin() {
        if (checkLocationPermission()) {
            // Case 1: Permission already granted (at least 'While In Use')
            checkBackgroundLocationPermissionAndStartService()
            return
        }

        // Case 2: Permission is not granted. Check if it's permanently denied ('Don't ask again').
        val shouldShowRationale = ActivityCompat.shouldShowRequestPermissionRationale(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        )

        if (shouldShowRationale) {
            // Temporary denial or first run rationale—show OS prompt
            val permissionsToRequest = mutableListOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )
            ActivityCompat.requestPermissions(
                this,
                permissionsToRequest.toTypedArray(),
                LOCATION_PERMISSION_REQUEST_CODE
            )
        } else {
            // Permission permanently denied (i.e., 'Don't ask again' was checked) OR first ever run.
            // We use the rationale check and the current permission status to determine permanent denial.
            // If rationale is false AND permission is NOT granted, it's permanent denial.
            val isPermanentlyDenied = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED

            if (isPermanentlyDenied) {
                showInitialPermissionDeniedDialog() // Guide user to settings
            } else {
                // If rationale is false but permission is not yet denied (first run only)
                val permissionsToRequest = mutableListOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                )
                ActivityCompat.requestPermissions(
                    this,
                    permissionsToRequest.toTypedArray(),
                    LOCATION_PERMISSION_REQUEST_CODE
                )
            }
        }
    }

    private fun startLocationService() {
        Log.d("MainActivity", "Starting Location Service...")
        val intent = Intent(this, LocationService::class.java)
        intent.putExtra("xMedsoftToken", xMedsoftToken)
        intent.putExtra("currentRoomId", currentRoomId)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(this, intent)
        } else {
            startService(intent)
        }
    }

    private fun stopLocationUpdates() {
        val intent = Intent(this, LocationService::class.java)
        stopService(intent)
    }

    private fun sendLocationToAPI(location: Location) {
        val medsoftToken = xMedsoftToken
        val roomId = currentRoomId

        if (medsoftToken == null || roomId == null) {
            Log.e("MainActivity", "Token or RoomId not available")
            return
        }

        val client = OkHttpClient()
        val url = "https://app.medsoft.care/api/location/save/patient"
        val mediaType = "application/json; charset=utf-8".toMediaType()

        val jsonBody = JSONObject()
        jsonBody.put("lat", location.latitude)
        jsonBody.put("lng", location.longitude)
        jsonBody.put("roomId", roomId)
        val requestBody = jsonBody.toString().toRequestBody(mediaType)

        val request = Request.Builder()
            .url(url)
            .post(requestBody)
            .addHeader("Authorization", "Bearer $medsoftToken")
            .addHeader("Content-Type", "application/json")
            .build()

        CoroutineScope(Dispatchers.IO).launch {
            try {
                client.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        Log.d("MainActivity", "Location sent successfully")
                    } else {
                        Log.e("MainActivity", "Failed to send location: ${response.code}")
                    }
                }
            } catch (e: IOException) {
                Log.e("MainActivity", "Error sending location: ${e.message}")
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                // Foreground permission granted, now check background
                checkBackgroundLocationPermissionAndStartService()
            } else {
                Log.e("MainActivity", "Location permission denied by user.")
            }
        }
    }
}
