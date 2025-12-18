// In android/app/src/main/kotlin/com/example/medsoft_patient/LocationService.kt

package com.example.medsoft_patient

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.location.Location
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority.PRIORITY_HIGH_ACCURACY
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.Locale

class LocationService : Service() {

    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var locationCallback: LocationCallback
    private var xMedsoftToken: String? = null
    private var currentRoomId: String? = null


    private var smallestDisplacement = 10f

    companion object {
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "LocationServiceChannel"
        private const val LOCATION_INTERVAL = 10000L // 10 seconds
        private const val FASTEST_LOCATION_INTERVAL = 5000L // 5 seconds
//        private const val SMALLEST_DISPLACEMENT = 5f // 10 meters (mimics iOS distanceFilter)
    }

    override fun onCreate() {
        super.onCreate()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        createNotificationChannel()
        // Error fix: startForeground call requires the service type in manifest
        startForeground(NOTIFICATION_ID, getNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let {
            xMedsoftToken = it.getStringExtra("xMedsoftToken")
            currentRoomId = it.getStringExtra("currentRoomId")
            Log.d("LocationService", "Service started. Token/Room: $xMedsoftToken / $currentRoomId")
        }

        startLocationUpdates()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        stopLocationUpdates()
        super.onDestroy()
    }

    private fun restartLocationUpdates() {
        Log.d(
            "LocationService",
            "Restarting location updates with new displacement: $smallestDisplacement meters"
        )
        stopLocationUpdates(stopForeground = false) // Stop without stopping the service/notification
        startLocationUpdates()
    }

    private fun startLocationUpdates() {
        try {
            val locationRequest = LocationRequest.Builder(PRIORITY_HIGH_ACCURACY, LOCATION_INTERVAL)
                .setMinUpdateIntervalMillis(FASTEST_LOCATION_INTERVAL)
                .setMinUpdateDistanceMeters(smallestDisplacement).build()

            locationCallback = object : LocationCallback() {
                override fun onLocationResult(locationResult: LocationResult) {
                    locationResult.lastLocation?.let { location ->
                        sendLocationToAPI(location)
                    }
                }
            }

            fusedLocationClient.requestLocationUpdates(locationRequest, locationCallback, null)
        } catch (e: SecurityException) {
            Log.e("LocationService", "Location permission is missing: ${e.message}")
        }
    }

    private fun stopLocationUpdates(stopForeground: Boolean = true) {
        if (::locationCallback.isInitialized) {
            fusedLocationClient.removeLocationUpdates(locationCallback)
        }
        if (stopForeground) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID, "Байршил тогтоох үйлчилгээ", NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun getNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID).setContentTitle("Байршил тогтоох")
            .setContentText("Өвчтөний байршлыг далд горимд хянаж байна.")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setPriority(NotificationCompat.PRIORITY_LOW).build()
    }

    private fun sendLocationToAPI(location: Location) {
        val medsoftToken = xMedsoftToken
        val roomId = currentRoomId

        if (medsoftToken == null || roomId == null) {
            Log.e("LocationService", "Error: Token or RoomId not available. Stopping service.")
            stopSelf()
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

        val request = Request.Builder().url(url).post(requestBody)
            .addHeader("Authorization", "Bearer $medsoftToken")
            .addHeader("Content-Type", "application/json").build()

        CoroutineScope(Dispatchers.IO).launch {
            try {
                client.newCall(request).execute().use { response ->
                    val responseBody = response.body?.string()

                    if (response.isSuccessful) {
                        val currentTime = java.text.SimpleDateFormat(
                            "yyyy-MM-dd HH:mm:ss", Locale.getDefault()
                        ).format(java.util.Date())
                        Log.d(
                            "LocationService",
                            "Location data sent successfully at $currentTime. Lat: ${location.latitude}, Lng: ${location.longitude}"
                        )
                        Log.d("LocationService", "API Response Body: $responseBody")
                        if (responseBody != null) {
                            try {
                                val json = JSONObject(responseBody)
                                val arrivedData = json.optJSONObject("data")
                                if (arrivedData != null) {
                                    // Warning fix: Check for optBoolean failure. It returns false if key is absent.
                                    val arrivedInFifty =
                                        arrivedData.optBoolean("arrivedInFifty", false)

                                    if (arrivedInFifty) {
                                        sendBroadcastToFlutter(
                                            "arrivedInFiftyReached"
                                        )
                                    }

                                    val distance = arrivedData.optDouble("distance", -1.0)
                                    if (distance > 0) {

                                        val newDisplacement =
                                            String.format(Locale.US, "%.2f", distance).toFloat()

                                        Log.d(
                                            "LocationService", "newDisplacement $newDisplacement"
                                        )


                                        if (newDisplacement != smallestDisplacement) {
                                            smallestDisplacement = newDisplacement
                                            restartLocationUpdates()
                                        }
                                    }
                                    Log.d(
                                        "LocationService", "arrivedData is null"
                                    )


                                }else{

                                }
                            } catch (e: Exception) {
                                Log.e("LocationService", "Failed to parse JSON for updates: $e")
                            }
                        }

                    } else {
                        Log.e(
                            "LocationService",
                            "Failed to send location data. Status code: ${response.code}"
                        )

                        if (response.code == 401 || response.code == 403) {
                            // Token expired, force log out in Flutter
                            sendBroadcastToFlutter("navigateToLogin")
                        }
                    }
                }
            } catch (e: IOException) {
                Log.e("LocationService", "Error making POST request: $e")
            }
        }
    }

    private fun sendBroadcastToFlutter(methodName: String) {
        val intent = Intent("com.example.medsoft_patient.FLUTTER_COMMUNICATION")
        intent.putExtra("method", methodName)
        intent.putExtra("value_bool", true)

        sendBroadcast(intent)
    }
}