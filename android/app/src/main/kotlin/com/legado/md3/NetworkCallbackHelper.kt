package com.legado.md3

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build

/**
 * 网络变化事件化（对齐 Sigma receiver/NetworkChangedListener.kt）：
 *  - API >= N：ConnectivityManager.registerDefaultNetworkCallback（onAvailable/onLost/
 *    onCapabilitiesChanged 均推送）；
 *  - API < N：CONNECTIVITY_ACTION 广播兼容分支。
 *
 * 变化时经 `legado/network` 通道主动 invokeMethod("onNetworkChanged", state)。
 * 保留原有 isWifi 查询能力（MainActivity 现有分支不受影响）。
 */
object NetworkCallbackHelper {

    @Volatile
    private var registered = false
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var receiver: BroadcastReceiver? = null
    private var appContext: Context? = null

    fun currentState(context: Context): Map<String, Any?> {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return mapOf("available" to false, "isWifi" to false, "type" to "none")
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val network = cm.activeNetwork
                val caps = network?.let { cm.getNetworkCapabilities(it) }
                stateOf(caps, network != null)
            } else {
                @Suppress("DEPRECATION")
                val info = cm.activeNetworkInfo
                val connected = info?.isConnected == true
                val t = if (!connected) "none" else when (info?.type) {
                    ConnectivityManager.TYPE_WIFI -> "wifi"
                    ConnectivityManager.TYPE_MOBILE -> "cellular"
                    ConnectivityManager.TYPE_ETHERNET -> "ethernet"
                    else -> "other"
                }
                mapOf(
                    "available" to connected,
                    "isWifi" to (connected && info?.type == ConnectivityManager.TYPE_WIFI),
                    "isCellular" to false,
                    "type" to t,
                    "validated" to connected,
                )
            }
        } catch (_: Exception) {
            mapOf("available" to false, "isWifi" to false, "type" to "none")
        }
    }

    private fun stateOf(caps: NetworkCapabilities?, present: Boolean): Map<String, Any?> {
        val wifi = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        val cellular = caps?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true
        val ethernet = caps?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true
        val validated = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
        } else {
            present
        }
        val type = when {
            wifi -> "wifi"
            cellular -> "cellular"
            ethernet -> "ethernet"
            present -> "other"
            else -> "none"
        }
        return mapOf(
            "available" to (present || caps != null),
            "isWifi" to wifi,
            "isCellular" to cellular,
            "type" to type,
            "validated" to validated,
        )
    }

    fun register(context: Context) {
        if (registered) return
        val app = context.applicationContext
        val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val cb = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        push(app)
                    }

                    override fun onLost(network: Network) {
                        push(app)
                    }

                    override fun onCapabilitiesChanged(
                        network: Network, networkCapabilities: NetworkCapabilities,
                    ) {
                        push(app)
                    }
                }
                cm.registerDefaultNetworkCallback(cb)
                callback = cb
            } else {
                @Suppress("DEPRECATION")
                val r = object : BroadcastReceiver() {
                    override fun onReceive(c: Context?, i: Intent?) {
                        push(app)
                    }
                }
                @Suppress("DEPRECATION", "UnspecifiedRegisterReceiverFlag")
                app.registerReceiver(r, IntentFilter(ConnectivityManager.CONNECTIVITY_ACTION))
                receiver = r
            }
            appContext = app
            registered = true
        } catch (_: Exception) {
            callback = null
            receiver = null
        }
    }

    private fun push(context: Context) {
        NativeChannels.emitNetworkChanged(currentState(context))
    }

    fun unregister() {
        val app = appContext
        val cm = app?.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                callback?.let { cm?.unregisterNetworkCallback(it) }
            } else {
                receiver?.let {
                    @Suppress("DEPRECATION")
                    app?.unregisterReceiver(it)
                }
            }
        } catch (_: Exception) {
        }
        callback = null
        receiver = null
        appContext = null
        registered = false
    }

    fun isRegistered(): Boolean = registered
}
