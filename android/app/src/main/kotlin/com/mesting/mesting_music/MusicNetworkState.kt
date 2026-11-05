package com.mesting.music

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ProxySelector
import java.net.URI
import java.util.concurrent.atomic.AtomicLong

/** Observes routing lifetime only. It never requests/binds a physical network,
 * changes VPN settings, or decides that an account has expired on connectivity.
 */
internal class MusicNetworkState(context: Context) : AutoCloseable {
    private val generation = AtomicLong()
    private val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private fun changed() { generation.incrementAndGet(); MusicHttpExchange.retireConnections() }
    private val capabilities = java.util.concurrent.ConcurrentHashMap<Network, String>()
    private val links = java.util.concurrent.ConcurrentHashMap<Network, String>()
    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { changed() }
        override fun onLost(network: Network) { capabilities.remove(network); links.remove(network); changed() }
        override fun onCapabilitiesChanged(network: Network, value: NetworkCapabilities) {
            // Signal strength changes do not invalidate TLS pools or increase
            // idle work. Only actual route/connectivity characteristics matter.
            val signature = listOf(value.hasTransport(NetworkCapabilities.TRANSPORT_VPN),
                value.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
                value.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
                value.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)).joinToString("|")
            if (capabilities.put(network, signature) != signature) changed()
        }
        override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) {
            val signature = "${properties.interfaceName}|${properties.dnsServers}|${properties.httpProxy}|${properties.linkAddresses}"
            if (links.put(network, signature) != signature) changed()
        }
    }
    private var registered = false
    init {
        try {
            if (Build.VERSION.SDK_INT >= 24) manager.registerDefaultNetworkCallback(callback)
            else manager.registerNetworkCallback(NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), callback)
            registered = true
        } catch (_: Exception) { /* Proxy/DNS lookups still use the current system route. */ }
    }
    fun policy(url: String): Map<String, Any> {
        val uri = URI(url)
        require(uri.host != null && uri.userInfo == null)
        val local = uri.host == "127.0.0.1" || uri.host == "localhost" || uri.host == "::1"
        val proxy = if (local) null else ProxySelector.getDefault()?.select(uri)
            ?.firstOrNull { it.type() == Proxy.Type.HTTP || it.type() == Proxy.Type.DIRECT }
        val address = proxy?.address() as? InetSocketAddress
        val proxyHost = address?.hostString?.let { if (it.contains(':')) "[$it]" else it }
        return mapOf("generation" to generation.get(), "proxy" to
            if (proxy?.type() == Proxy.Type.HTTP && address != null)
                "PROXY $proxyHost:${address.port}" else "DIRECT")
    }
    override fun close() {
        if (registered) try { manager.unregisterNetworkCallback(callback) } catch (_: Exception) {}
        registered = false
    }
}
