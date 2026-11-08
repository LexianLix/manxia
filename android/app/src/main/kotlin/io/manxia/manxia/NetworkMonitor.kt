package io.manxia.manxia

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

class NetworkMonitor(context: Context) : EventChannel.StreamHandler {
    private val manager = context.getSystemService(ConnectivityManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var registered = false
    private var trackedNetwork: Network? = null
    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            handler.post { trackedNetwork = network }
        }
        override fun onLost(network: Network) {
            handler.post {
                if (trackedNetwork == network) {
                    trackedNetwork = null
                    sink?.success(mapOf("kind" to "none", "metered" to true))
                }
            }
        }
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
            // Callback payloads are current; synchronous queries here can still
            // return the lost network on Android 15 and leave Wi-Fi stuck.
            val value = fromCapabilities(capabilities)
            handler.post {
                if (trackedNetwork == network) sink?.success(value)
            }
        }
    }
    private fun fromCapabilities(capabilities: NetworkCapabilities?): Map<String, Any> {
        val kind = when {
            capabilities == null -> "none"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            else -> "other"
        }
        return mapOf("kind" to kind, "metered" to (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) != true))
    }
    fun state(): Map<String, Any> {
        return try {
            val network = manager.activeNetwork
            val capabilities = network?.let { manager.getNetworkCapabilities(it) }
            fromCapabilities(capabilities)
        } catch (_: Exception) { mapOf("kind" to "unknown", "metered" to true) }
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        trackedNetwork = manager.activeNetwork
        if (!registered) {
            try { manager.registerDefaultNetworkCallback(callback); registered = true }
            catch (error: Exception) {
                android.util.Log.w("ManxiaNetwork", "Unable to observe default network", error)
                events.error("network", "无法监听网络变化", null)
                return
            }
        }
        sink?.success(state())
    }
    override fun onCancel(arguments: Any?) { close() }
    fun close() {
        sink = null
        trackedNetwork = null
        if (registered) {
            try { manager.unregisterNetworkCallback(callback) } catch (_: Exception) { }
            registered = false
        }
    }
}
