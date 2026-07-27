package app.mise.driver.location

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.location.Location
import android.os.*
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.UUID
import java.util.concurrent.Executors

class MiseLocationService : Service() {
    companion object {
        val TRACKABLE_STATES = setOf("available","assigned","at_pickup","delivering","returning")
        const val QUEUE_LIMIT = 100
        const val CHANNEL = "mise_active_location"
    }
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var fused: FusedLocationProviderClient
    private lateinit var prefs: SharedPreferences
    private var state = "offline"
    private var driverVersion = 0
    private var policyEnabled = false
    private var uploading = false
    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            result.lastLocation?.let { worker.execute { enqueue(it); flush() } }
        }
    }

    override fun onCreate() {
        super.onCreate()
        prefs = SecureGpsStore.open(this)
        fused = LocationServices.getFusedLocationProviderClient(this)
        val channel = NotificationChannel(CHANNEL, "Aktive Standortfreigabe", NotificationManager.IMPORTANCE_LOW)
        channel.description = "Sichtbar, solange eine autorisierte Lieferschicht Standorttracking verwendet."
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(applicationInfo.icon).setContentTitle("Mise Driver Standort aktiv")
            .setContentText("Autorisierte Schicht wird geprüft.")
            .setOngoing(true).setCategory(Notification.CATEGORY_SERVICE).build()
        startForeground(280, notification)
        worker.execute { authorizeFromCanonicalSnapshot() }
        return START_NOT_STICKY
    }

    private fun authorizeFromCanonicalSnapshot() {
        val token = prefs.getString("access_token",null)
            ?: return stopUpdates()
        try {
            val connection = URL("https://mise-gastro.de/api/driver/v2/snapshot").openConnection() as HttpURLConnection
            connection.connectTimeout=15_000; connection.readTimeout=15_000
            connection.setRequestProperty("Authorization","Bearer $token")
            if(connection.responseCode != 200) { connection.disconnect(); return stopUpdates() }
            val root = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            val snapshot = root.getJSONObject("snapshot")
            val driver = snapshot.getJSONObject("driver")
            val gps = snapshot.getJSONObject("gps_transport")
            state = driver.getString("state"); driverVersion = driver.getInt("version")
            policyEnabled = gps.optBoolean("policy_enabled",false)
            connection.disconnect()
        } catch (_: Exception) { return stopUpdates() }
        if (!policyEnabled || state !in TRACKABLE_STATES || !hasPermission()) return stopUpdates()
        val authority="${state}:${driverVersion}"
        if(prefs.getString("authority",null)!=authority) {
            prefs.edit().putString("authority",authority).remove("session").putLong("sequence",0).apply()
        }
        Handler(Looper.getMainLooper()).post { beginTracking() }
    }

    private fun beginTracking() {
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 15_000)
            .setMinUpdateDistanceMeters(15f).setMaxUpdateDelayMillis(30_000).build()
        if (!hasPermission()) return stopUpdates()
        fused.requestLocationUpdates(request, callback, Looper.getMainLooper())
        worker.execute { flush() }
    }

    private fun hasPermission() =
        ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun stopUpdates() {
        if (::fused.isInitialized) fused.removeLocationUpdates(callback)
        stopForeground(STOP_FOREGROUND_REMOVE); stopSelf()
    }

    private fun enqueue(location: Location) {
        val session = prefs.getString("session", null) ?: UUID.randomUUID().toString().also {
            prefs.edit().putString("session", it).apply()
        }
        val sequence = prefs.getLong("sequence", 0) + 1
        prefs.edit().putLong("sequence", sequence).apply()
        val action = UUID.randomUUID().toString()
        val payload = JSONObject()
            .put("session_id",session).put("sequence",sequence)
            .put("captured_at", Instant.ofEpochMilli(location.time).toString())
            .put("latitude",location.latitude).put("longitude",location.longitude)
            .put("accuracy_m",location.accuracy.toDouble())
            .put("speed_mps",if(location.hasSpeed()) location.speed.toDouble() else JSONObject.NULL)
            .put("heading_deg",if(location.hasBearing()) location.bearing.toDouble() else JSONObject.NULL)
            .put("app_version",packageManager.getPackageInfo(packageName,0).versionName ?: "unknown")
            .put("app_build",packageManager.getPackageInfo(packageName,0).longVersionCode.toString())
            .put("platform","android").put("app_state","background")
            .put("permission_state","always").put("network_state","unknown")
            .put("capability_flags",JSONObject().put("foreground_service",true))
        val envelope = JSONObject().put("action_id",action).put("expected_state",state)
            .put("expected_versions",JSONObject().put("driver",driverVersion)).put("payload",payload)
        val queue = readQueue()
        queue.put(envelope)
        while(queue.length()>QUEUE_LIMIT) queue.remove(0)
        prefs.edit().putString("queue",queue.toString()).commit()
    }

    private fun readQueue() = try { JSONArray(prefs.getString("queue","[]")) } catch (_: Exception) { JSONArray() }

    private fun flush() {
        if(uploading) return
        val token = prefs.getString("access_token",null) ?: return
        val queue = readQueue(); if(queue.length()==0) return
        uploading=true
        try {
            val connection = URL("https://mise-gastro.de/api/driver/v2/gps/events").openConnection() as HttpURLConnection
            connection.requestMethod="POST"; connection.connectTimeout=15_000; connection.readTimeout=15_000
            connection.setRequestProperty("Authorization","Bearer $token")
            connection.setRequestProperty("Content-Type","application/json")
            connection.doOutput=true
            connection.outputStream.use { it.write(queue.getJSONObject(0).toString().toByteArray()) }
            val status=connection.responseCode
            if(status in 200..299) {
                queue.remove(0); prefs.edit().putString("queue",queue.toString()).commit()
            } else if(status==409 || status in 400..499 && status!=429) {
                // Immutable stale/invalid head is terminal. Keep only reason
                // metadata, discard coordinates, and unblock later events.
                val reason=try { JSONObject(connection.errorStream.bufferedReader().use{it.readText()}).optString("reason_code","terminal_http_$status") } catch (_:Exception) { "terminal_http_$status" }
                prefs.edit().putString("last_quarantine_reason",reason).apply()
                queue.remove(0); prefs.edit().putString("queue",queue.toString()).commit()
                authorizeFromCanonicalSnapshot()
            } else {
                val head=queue.getJSONObject(0)
                val attempts=head.optInt("transport_attempts",0)+1
                if(attempts>=6) {
                    prefs.edit().putString("last_quarantine_reason","retry_exhausted").apply()
                    queue.remove(0)
                } else head.put("transport_attempts",attempts)
                prefs.edit().putString("queue",queue.toString()).commit()
            }
            connection.disconnect()
        } catch (_: Exception) { /* durable queue retries at next callback/start */ }
        finally { uploading=false }
        if(queue.length()>0) Handler(Looper.getMainLooper()).postDelayed({ worker.execute { flush() } },15_000)
    }

    override fun onDestroy() { if(::fused.isInitialized) fused.removeLocationUpdates(callback); worker.shutdown(); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null
}
