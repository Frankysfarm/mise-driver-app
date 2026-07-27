package app.mise.driver

import android.os.Bundle
import com.getcapacitor.BridgeActivity
import app.mise.driver.location.MiseLocationBridge

class MainActivity : BridgeActivity() {
    private lateinit var locationBridge: MiseLocationBridge
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        locationBridge=MiseLocationBridge(this)
    }
    override fun onResume() {
        super.onResume()
        // Capacitor Preferences is only a handoff surface. The bridge moves
        // the bearer into Android Keystore-backed encrypted preferences.
        val handoff=getSharedPreferences("CapacitorStorage",MODE_PRIVATE)
        val token=handoff.getString("mise_access_token",null)
        locationBridge.reconcile(token ?: SecureTokenAccess.current(this))
        if(token!=null) handoff.edit().remove("mise_access_token").apply()
    }
    override fun onDestroy() { if(isFinishing) locationBridge.stop(); super.onDestroy() }
}
