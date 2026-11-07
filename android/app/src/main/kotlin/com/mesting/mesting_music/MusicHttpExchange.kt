package com.mesting.music

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.IOException
import java.net.ProxySelector
import java.net.SocketTimeoutException
import java.net.URI
import java.net.URL
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.GZIPInputStream
import java.util.zip.InflaterInputStream
import okhttp3.Call
import okhttp3.ConnectionPool
import okhttp3.CookieJar
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import okhttp3.Protocol
import okhttp3.ResponseBody.Companion.toResponseBody
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okio.BufferedSink

/** Shared system DNS/proxy/TLS for finalized Dart/Rust wire requests. Address
 * races finish before dispatch; no account write is retried after dispatch.
 * Cookie ownership stays with the repositories, never a global jar.
 */
internal object MusicHttpExchange {
    private val deadlines = java.util.concurrent.ScheduledThreadPoolExecutor(1) { runnable ->
        Thread(runnable, "mesting.http.deadline").apply { isDaemon = true }
    }.apply { removeOnCancelPolicy = true }

    // HTTP503/421 can trigger library follow-ups even with connection retries
    // disabled. Return the real receipt without implicitly repeating an action,
    // including legacy GET endpoints that send SMS or perform authentication.
    private class Receipt(val response: Response) : IOException("Music HTTP receipt")
    @Volatile private var base = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS).readTimeout(12, TimeUnit.SECONDS)
        .writeTimeout(12, TimeUnit.SECONDS).fastFallback(true)
        .retryOnConnectionFailure(false).followRedirects(false).followSslRedirects(false)
        .cookieJar(CookieJar.NO_COOKIES)
        // Original Rust traffic was HTTP/1.1. Fresh short-lived API sockets
        // also avoid an old HTTP/2 pool surviving a VPN node/route transition.
        .protocols(listOf(Protocol.HTTP_1_1))
        .addNetworkInterceptor { chain ->
            val reply = chain.proceed(chain.request())
            if (reply.code in setOf(408, 421, 503)) {
                val mediaType = reply.body.contentType()
                val body = reply.body.bytes()
                val receipt = Response.Builder().request(reply.request).protocol(reply.protocol)
                    .code(reply.code).message(reply.message).headers(reply.headers)
                    .body(body.toResponseBody(mediaType)).build()
                reply.close()
                throw Receipt(receipt)
            }
            reply
        }.build()

    /** New calls do not reuse a connection from a prior VPN/default route.
     * Active streams may finish; credentials and user queues are untouched.
     */
    @Synchronized fun retireConnections() {
        val previous = base
        base = previous.newBuilder().connectionPool(ConnectionPool()).build()
        previous.connectionPool.evictAll()
    }

    class Task {
        val cancelled = AtomicBoolean(false)
        val expired = AtomicBoolean(false)
        @Volatile var call: Call? = null
        @Volatile var response: Response? = null
        fun cancel() { cancelled.set(true); call?.cancel() }
        fun release() { response?.close(); response = null; call = null }
        fun check() {
            if (expired.get()) throw SocketTimeoutException("Music deadline")
            if (cancelled.get()) throw InterruptedException("Cancelled")
        }
    }
    class Opened(val status: Int, val headers: Map<String, List<String>>,
        val stream: InputStream?, val finalUrl: String, val task: Task) : AutoCloseable {
        override fun close() { try { stream?.close() } finally { task.release() } }
    }
    data class Reply(val status: Int, val headers: Map<String, List<String>>,
        val body: ByteArray, val finalUrl: String)

    fun validate(url: String) {
        val uri = URI(url)
        require(uri.scheme == "https" || uri.scheme == "http")
        require(uri.host != null && uri.rawUserInfo == null && uri.fragment == null)
        require(uri.port == -1 || uri.port in 1..65535)
    }

    fun open(method: String, url: String, headers: Map<String, String>, body: ByteArray,
        followRedirects: Boolean, task: Task, client: OkHttpClient? = null): Opened {
        require(method in setOf("GET", "POST", "PUT", "DELETE", "HEAD", "PATCH"))
        var currentUrl = url; var currentMethod = method
        var currentBody = body; var currentHeaders = headers
        for (redirect in 0..10) {
            validate(currentUrl); task.check()
            val builder = Request.Builder().url(currentUrl)
            currentHeaders.forEach { (key, value) ->
                require(!key.contains('\r') && !key.contains('\n') && !value.contains('\r') && !value.contains('\n'))
                if (!key.equals("Content-Length", true) && !key.equals("Connection", true) &&
                    !key.equals("Accept-Encoding", true)) builder.header(key, value)
            }
            builder.header("Connection", "close")
            val requestBody = if (currentBody.isNotEmpty() || currentMethod in setOf("POST", "PUT", "PATCH")) {
                val data = currentBody
                val mediaType = currentHeaders.entries.firstOrNull { it.key.equals("Content-Type", true) }
                    ?.value?.toMediaTypeOrNull()
                object : RequestBody() {
                    override fun contentType() = mediaType
                    override fun contentLength() = data.size.toLong()
                    override fun isOneShot() = true
                    override fun writeTo(sink: BufferedSink) { sink.write(data) }
                }
            } else null
            builder.method(currentMethod, requestBody)
            // Refresh the system selector per request; never replace it globally.
            val actualClient = client ?: base.newBuilder().apply {
                ProxySelector.getDefault()?.let { proxySelector(it) }
            }.build()
            val call = actualClient.newCall(builder.build()); task.call = call
            task.check()
            val response = try { call.execute() } catch (receipt: Receipt) {
                if (receipt.response.code == 421) retireConnections()
                receipt.response
            }
            task.response = response; task.check()
            val status = response.code
            // Repeated cookies stay in server order: expiration then replacement.
            val responseHeaders = response.headers.names().associate { name ->
                name.lowercase() to response.headers.values(name) }
            val location = response.header("Location")
            if (followRedirects && status in setOf(301, 302, 303, 307, 308) && location != null &&
                (currentMethod == "GET" || currentMethod == "HEAD" || status == 303)) {
                val destination = URL(URL(currentUrl), location)
                require(URL(currentUrl).protocol != "https" || destination.protocol == "https")
                if (!URL(currentUrl).host.equals(destination.host, true)) {
                    currentHeaders = currentHeaders.filterKeys { it.lowercase() in
                        setOf("accept", "accept-language", "user-agent", "range") }
                }
                if (status == 303 && currentMethod != "HEAD") { currentMethod = "GET"; currentBody = byteArrayOf() }
                task.release(); currentUrl = destination.toString(); continue
            }
            val encoding = response.header("Content-Encoding")?.trim()?.lowercase()
            val raw = response.body.byteStream()
            val input = when (encoding) {
                "gzip" -> GZIPInputStream(raw)
                "deflate" -> InflaterInputStream(raw)
                else -> raw
            }
            val decodedHeaders = if (encoding == "gzip" || encoding == "deflate")
                responseHeaders.filterKeys { it != "content-encoding" && it != "content-length" }
                else responseHeaders
            return Opened(status, decodedHeaders, input, currentUrl, task)
        }
        throw IllegalArgumentException("Too many redirects")
    }

    fun execute(method: String, url: String, headers: Map<String, String>, body: ByteArray,
        timeoutMs: Long, followRedirects: Boolean, maxBytes: Int, task: Task,
        client: OkHttpClient? = null): Reply {
        val deadline = deadlines.schedule({ task.expired.set(true); task.cancel() },
            timeoutMs.coerceIn(100, 180000), TimeUnit.MILLISECONDS)
        try {
            open(method, url, headers, body, followRedirects, task, client).use { response ->
                val bytes = ByteArrayOutputStream()
                response.stream?.use { stream ->
                    val buffer = ByteArray(65536)
                    while (true) {
                        task.check(); val count = stream.read(buffer)
                        if (count < 0) break
                        require(bytes.size().toLong() + count <= maxBytes)
                        bytes.write(buffer, 0, count)
                    }
                }
                task.check()
                return Reply(response.status, response.headers, bytes.toByteArray(), response.finalUrl)
            }
        } catch (error: Exception) { task.check(); throw error }
        finally { deadline.cancel(false); task.release() }
    }
}
