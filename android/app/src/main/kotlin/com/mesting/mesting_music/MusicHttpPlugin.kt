package com.mesting.music

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.SSLException

/** Bounded JSON transport using Android's current system routing and trust store.
 * Never binds Wi-Fi/mobile, installs a proxy, weakens TLS or replays a request.
 * Connections/cookies are request-local; authentication remains owned by Dart.
 */
class MusicHttpPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private val workers = Executors.newFixedThreadPool(6)
    private class Task {
        val cancelled = AtomicBoolean(false)
        @Volatile var connection: HttpURLConnection? = null
        fun cancel() { cancelled.set(true); connection?.disconnect() }
    }
    private val tasks = ConcurrentHashMap<String, Task>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.mesting.music/network")
        channel.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        tasks.values.forEach { it.cancel() }
        workers.shutdownNow()
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id") ?: ""
        if (call.method == "cancel") {
            tasks[id]?.cancel()
            result.success(null)
            return
        }
        if (call.method != "send") { result.notImplemented(); return }
        val task = Task()
        if (id.isEmpty() || tasks.size >= 48 || tasks.putIfAbsent(id, task) != null) {
            result.error("connection", "Request unavailable", null); return
        }
        workers.execute {
            try {
                val url = URL(call.argument<String>("url") ?: "")
                val host = url.host.lowercase()
                require(url.protocol == "https" && url.userInfo == null &&
                    (url.port == -1 || url.port == 443) &&
                    (host == "music.163.com" || host.endsWith(".music.163.com") ||
                     host == "kugou.com" || host.endsWith(".kugou.com")))
                val method = call.argument<String>("method") ?: "GET"
                require(method == "GET" || method == "POST")
                val body = call.argument<ByteArray>("body") ?: byteArrayOf()
                require(body.size <= 8 * 1024 * 1024)
                if (task.cancelled.get()) throw InterruptedException()
                // URL.openConnection honors Android's ProxySelector. Socket
                // routing and DNS remain on the default network, including VPN.
                val connection = url.openConnection() as HttpURLConnection
                task.connection = connection
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 8000
                connection.readTimeout = 12000
                connection.useCaches = false
                connection.requestMethod = method
                (call.argument<Map<String, String>>("headers") ?: emptyMap()).forEach { (key, value) ->
                    require(!key.contains('\r') && !key.contains('\n') && !value.contains('\r') && !value.contains('\n'))
                    // Cookie jars and response caching must never be global.
                    connection.setRequestProperty(key, value)
                }
                // These short JSON transactions must not retain a socket from
                // the previous VPN/default-network lifetime. Audio streams are
                // owned separately by the native player, not by this bridge.
                connection.setRequestProperty("Connection", "close")
                if (task.cancelled.get()) throw InterruptedException()
                if (body.isNotEmpty()) {
                    connection.doOutput = true
                    connection.setFixedLengthStreamingMode(body.size)
                    connection.outputStream.use { it.write(body) }
                }
                val status = connection.responseCode
                val headers = connection.headerFields.entries.filter { it.key != null }
                    .associate { it.key!!.lowercase() to it.value.joinToString(", ") }
                val bytes = ByteArrayOutputStream()
                val input = if (status >= 400) connection.errorStream else connection.inputStream
                input?.use { stream ->
                    val buffer = ByteArray(16384)
                    while (true) {
                        if (task.cancelled.get()) throw InterruptedException()
                        val count = stream.read(buffer)
                        if (count < 0) break
                        require(bytes.size() + count <= 16 * 1024 * 1024)
                        bytes.write(buffer, 0, count)
                    }
                }
                if (task.cancelled.get()) throw InterruptedException()
                val response = mapOf("status" to status, "headers" to headers, "body" to bytes.toByteArray())
                main.post { if (task.cancelled.get()) result.error("cancelled", "Cancelled", null) else result.success(response) }
            } catch (error: Exception) {
                val category = when {
                    task.cancelled.get() || error is InterruptedException -> "cancelled"
                    error is UnknownHostException -> "dns"
                    error is SSLException -> "tls"
                    error is SocketTimeoutException -> "timeout"
                    error is IllegalArgumentException -> "format"
                    else -> "connection"
                }
                // Raw exceptions can embed signed URLs and credentials.
                main.post { result.error(category, "Music request failed", null) }
            } finally {
                task.connection?.disconnect()
                tasks.remove(id)
            }
        }
    }
}
