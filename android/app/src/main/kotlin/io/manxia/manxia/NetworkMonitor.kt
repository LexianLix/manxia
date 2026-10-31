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
    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = publish()
        override fun onLost(network: Network) = publish()
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = publish()
    }
    fun state(): Map<String, Any> {
        return try {
            val network = manager.activeNetwork
            val capabilities = network?.let { manager.getNetworkCapabilities(it) }
            val kind = when {
                capabilities == null -> "none"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
                else -> "other"
            }
            mapOf("kind" to kind, "metered" to manager.isActiveNetworkMetered)
        } catch (_: Exception) { mapOf("kind" to "unknown", "metered" to true) }
    }
    private fun publish() { handler.post { sink?.success(state()) } }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        if (!registered) {
            try { manager.registerDefaultNetworkCallback(callback); registered = true }
            catch (_: Exception) { }
        }
        publish()
    }
    override fun onCancel(arguments: Any?) { close() }
    fun close() {
        sink = null
        if (registered) {
            try { manager.unregisterNetworkCallback(callback) } catch (_: Exception) { }
            registered = false
        }
    }
}
