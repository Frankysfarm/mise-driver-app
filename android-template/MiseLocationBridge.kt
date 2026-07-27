package app.mise.driver.location

import android.content.*
import android.os.Build
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

class MiseLocationBridge(private val context: Context) {
    private val worker=Executors.newSingleThreadExecutor()

    // Called from the authenticated shell on resume/login/session changes.
    fun reconcile(accessToken: String?) {
        if(accessToken.isNullOrBlank()) return stop()
        val secure=SecureGpsStore.open(context)
        secure.edit().putString("access_token",accessToken).apply()
        worker.execute {
            try {
                val c=URL("https://mise-gastro.de/api/driver/v2/snapshot").openConnection() as HttpURLConnection
                c.setRequestProperty("Authorization","Bearer $accessToken")
                c.connectTimeout=15_000;c.readTimeout=15_000
                if(c.responseCode!=200) { c.disconnect(); return@execute stop() }
                val snapshot=JSONObject(c.inputStream.bufferedReader().use{it.readText()}).getJSONObject("snapshot")
                val driver=snapshot.getJSONObject("driver");val gps=snapshot.getJSONObject("gps_transport")
                val allowed=gps.optBoolean("policy_enabled",false) &&
                    driver.getString("state") in MiseLocationService.TRACKABLE_STATES
                c.disconnect()
                if(!allowed) return@execute stop()
                val intent=Intent(context,MiseLocationService::class.java)
                if(Build.VERSION.SDK_INT>=26) context.startForegroundService(intent) else context.startService(intent)
            } catch (_:Exception) { stop() }
        }
    }
    fun stop() {
        SecureGpsStore.open(context).edit().remove("authority").remove("session").putLong("sequence",0).apply()
        context.stopService(Intent(context,MiseLocationService::class.java))
    }
}
