package app.mise.driver

import android.content.Context
import app.mise.driver.location.SecureGpsStore

object SecureTokenAccess {
    fun current(context:Context)=SecureGpsStore.open(context).getString("access_token",null)
}
