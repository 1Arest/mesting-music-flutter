package com.mesting.music

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import javax.net.ssl.SSLException

/** Bounded JSON transport using Android's current system routing and trust store.
 * Never binds Wi-Fi/mobile, installs a proxy, weakens TLS or replays a request.
 * Connections/cookies are request-local; authentication remains owned by Dart.
 */
class MusicHttpPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private val workers = Executors.newFixedThreadPool(6)
    private val policyWorkers = Executors.newFixedThreadPool(2)
    private val dnsWorkers = Executors.newFixedThreadPool(2)
    private val tasks = ConcurrentHashMap<String, MusicHttpExchange.Task>()
    private var networkState: MusicNetworkState? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        networkState = MusicNetworkState(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, "com.mesting.music/network")
        channel.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        networkState?.close()
        networkState = null
        channel.setMethodCallHandler(null)
        tasks.values.forEach { it.cancel() }
        workers.shutdownNow()
        policyWorkers.shutdownNow()
        dnsWorkers.shutdownNow()
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method in setOf("prepareKugou", "policy", "resolve")) {
            (if (call.method == "resolve") dnsWorkers else policyWorkers).execute {
                try {
                    val value: Any = when (call.method) {
                        "prepareKugou" -> { MusicNativeTransport.install(); true }
                        "policy" -> networkState!!.policy(call.argument<String>("url") ?: "")
                        else -> java.net.InetAddress.getAllByName(call.argument<String>("host") ?: "")
                            .mapNotNull { it.hostAddress }
                    }
                    main.post { result.success(value) }
                } catch (_: Throwable) {
                    main.post { result.error(if (call.method == "resolve") "dns" else "connection",
                        "Music transport unavailable", null) }
                }
            }
            return
        }
        val id = call.argument<String>("id") ?: ""
        if (call.method == "cancel") {
            tasks[id]?.cancel()
            result.success(null)
            return
        }
        if (call.method != "send") { result.notImplemented(); return }
        val task = MusicHttpExchange.Task()
        if (id.isEmpty() || tasks.size >= 48 || tasks.putIfAbsent(id, task) != null) {
            result.error("connection", "Request unavailable", null); return
        }
        workers.execute {
            try {
                val url = URL(call.argument<String>("url") ?: "")
                val host = url.host.lowercase()
                require(url.protocol == "https" && url.userInfo == null &&
                    (url.port == -1 || url.port == 443) &&
                    (host == "beta-luna.douyin.com" || host == "api.qishui.com" ||
                     host == "music.163.com" || host.endsWith(".music.163.com") ||
                     host == "kugou.com" || host.endsWith(".kugou.com")))
                val method = call.argument<String>("method") ?: "GET"
                require(method == "GET" || method == "POST")
                val body = call.argument<ByteArray>("body") ?: byteArrayOf()
                require(body.size <= 8 * 1024 * 1024)
                val reply = MusicHttpExchange.execute(method, url.toString(),
                    call.argument<Map<String, String>>("headers") ?: emptyMap(), body,
                    18000L, false, 16 * 1024 * 1024, task)
                val headers = reply.headers.mapValues { it.value.joinToString(", ") }
                val response = mapOf("status" to reply.status, "headers" to headers, "body" to reply.body)
                main.post {
                    when {
                        task.expired.get() -> result.error("timeout", "Music deadline", null)
                        task.cancelled.get() -> result.error("cancelled", "Cancelled", null)
                        else -> result.success(response)
                    }
                }
            } catch (error: Exception) {
                val category = when {
                    task.expired.get() -> "timeout"
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
                task.release()
                tasks.remove(id)
            }
        }
    }
}
