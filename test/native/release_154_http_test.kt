package com.mesting.music

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.net.SocketTimeoutException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import java.util.zip.GZIPOutputStream
import java.io.ByteArrayOutputStream
import java.net.Socket
import java.net.SocketAddress
import java.net.InetAddress
import java.net.Inet6Address
import java.net.Proxy
import java.net.CookieHandler
import java.net.CookieManager
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.net.SocketFactory
import okhttp3.OkHttpClient

/** Runs real loopback HTTP against production exchange code, no account/device. */
fun main() {
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val executor = Executors.newCachedThreadPool()
    server.executor = executor
    val postCount = AtomicInteger()
    val redirectedPosts = AtomicInteger()
    val unavailableCount = AtomicInteger()
    val binary = ByteArray(180003) { (it % 251).toByte() }
    fun endpoint(path: String, handler: (com.sun.net.httpserver.HttpExchange) -> Unit) {
        server.createContext(path) { exchange ->
            try { handler(exchange) } finally { exchange.close() }
        }
    }
    endpoint("/echo") {
        postCount.incrementAndGet()
        val body = it.requestBody.readBytes()
        check(body.contentEquals(binary))
        it.sendResponseHeaders(200, body.size.toLong()); it.responseBody.write(body)
    }
    endpoint("/cookies") {
        it.responseHeaders.add("Set-Cookie", "fixture=expired; Max-Age=0")
        it.responseHeaders.add("Set-Cookie", "fixture=current; Path=/")
        it.sendResponseHeaders(200, 2); it.responseBody.write("ok".toByteArray())
    }
    endpoint("/gzip") {
        val output = ByteArrayOutputStream()
        GZIPOutputStream(output).use { gzip -> gzip.write(binary) }
        val body = output.toByteArray()
        it.responseHeaders.add("Content-Encoding", "gzip")
        it.sendResponseHeaders(200, body.size.toLong()); it.responseBody.write(body)
    }
    endpoint("/redirect") {
        it.responseHeaders.add("Location", "http://localhost:${server.address.port}/check-cookie")
        it.sendResponseHeaders(302, -1)
    }
    endpoint("/check-cookie") {
        check(it.requestHeaders.getFirst("Cookie") == null)
        check(it.requestHeaders.getFirst("Authorization") == null)
        it.sendResponseHeaders(200, 2); it.responseBody.write("ok".toByteArray())
    }
    endpoint("/post-redirect") {
        it.requestBody.readBytes()
        it.responseHeaders.add("Location", "/should-not-replay")
        it.sendResponseHeaders(307, -1)
    }
    endpoint("/should-not-replay") { redirectedPosts.incrementAndGet(); it.sendResponseHeaders(204, -1) }
    endpoint("/error") { it.sendResponseHeaders(429, 4); it.responseBody.write("busy".toByteArray()) }
    endpoint("/unavailable") {
        unavailableCount.incrementAndGet()
        it.responseHeaders.add("Retry-After", "0")
        it.sendResponseHeaders(503, 4); it.responseBody.write("busy".toByteArray())
    }
    endpoint("/slow") {
        it.sendResponseHeaders(200, 10)
        it.responseBody.write(byteArrayOf(1)); it.responseBody.flush()
        Thread.sleep(350)
        try { it.responseBody.write(ByteArray(9)) } catch (_: Exception) {}
    }
    endpoint("/large") {
        val size = 18 * 1024 * 1024
        it.sendResponseHeaders(200, size.toLong())
        val chunk = ByteArray(65536) { 7 }
        repeat(size / chunk.size) { _ -> it.responseBody.write(chunk) }
    }
    server.start()
    val base = "http://127.0.0.1:${server.address.port}"
    fun send(path: String, method: String = "GET", headers: Map<String, String> = emptyMap(),
        body: ByteArray = byteArrayOf(), follow: Boolean = true) =
        MusicHttpExchange.execute(method, base + path, headers, body, 3000, follow,
            32 * 1024 * 1024, MusicHttpExchange.Task())
    var passed = 0
    try {
        check(send("/echo", "POST", mapOf("Content-Type" to "application/octet-stream"), binary).body.contentEquals(binary))
        check(postCount.get() == 1); passed++
        val cookies = send("/cookies").headers["set-cookie"]!!
        check(cookies.size == 2 && cookies[0].contains("expired") && cookies[1].contains("current")); passed++
        val gzip = send("/gzip")
        check(gzip.body.contentEquals(binary) && !gzip.headers.containsKey("content-encoding")); passed++
        check(send("/redirect", headers = mapOf("Cookie" to "fixture=private", "Authorization" to "fixture-auth")).status == 200); passed++
        check(send("/redirect", follow = false).status == 302); passed++
        check(send("/post-redirect", "POST", body = byteArrayOf(1)).status == 307)
        check(redirectedPosts.get() == 0); passed++
        val error = send("/error"); check(error.status == 429 && String(error.body) == "busy"); passed++
        val task = MusicHttpExchange.Task()
        var timedOut = false
        try { MusicHttpExchange.execute("GET", "$base/slow", emptyMap(), byteArrayOf(),
            100, false, 1000, task) } catch (_: SocketTimeoutException) { timedOut = true }
        check(timedOut && task.expired.get()); passed++
        MusicHttpExchange.open("GET", "$base/large", emptyMap(), byteArrayOf(), true,
            MusicHttpExchange.Task()).use { response ->
            val chunk = ByteArray(65536); var total = 0
            while (true) { val size = response.stream!!.read(chunk); if (size < 0) break; total += size }
            check(total == 18 * 1024 * 1024)
        }; passed++
        var rejected = false
        try { MusicHttpExchange.validate("http://fixture:secret@localhost/") }
        catch (_: IllegalArgumentException) { rejected = true }
        check(rejected); passed++
        val unavailable = send("/unavailable")
        check(unavailable.status == 503 && String(unavailable.body) == "busy")
        check(unavailableCount.get() == 1); passed++
        val oldCookies = CookieHandler.getDefault()
        try {
            val manager = CookieManager()
            manager.cookieStore.add(java.net.URI(base), java.net.HttpCookie("fixture", "must-not-leak"))
            CookieHandler.setDefault(manager)
            check(send("/check-cookie").status == 200)
        } finally { CookieHandler.setDefault(oldCookies) }
        passed++
        val blocked = CountDownLatch(1)
        val ipv6Closed = AtomicInteger()
        val ipv6Started = AtomicInteger()
        val factory = object : SocketFactory() {
            override fun createSocket(): Socket = object : Socket() {
                private var isIpv6 = false
                override fun connect(address: SocketAddress, timeout: Int) {
                    if ((address as InetSocketAddress).address is Inet6Address) {
                        isIpv6 = true; ipv6Started.incrementAndGet()
                        blocked.await(5, TimeUnit.SECONDS)
                        throw java.net.SocketException("blocked IPv6 fixture")
                    }
                    super.connect(address, timeout)
                }
                override fun close() {
                    if (isIpv6) { ipv6Closed.incrementAndGet(); blocked.countDown() }
                    super.close()
                }
            }
            override fun createSocket(host: String, port: Int) = Socket(host, port)
            override fun createSocket(host: String, port: Int, local: InetAddress, localPort: Int) = Socket(host, port, local, localPort)
            override fun createSocket(host: InetAddress, port: Int) = Socket(host, port)
            override fun createSocket(host: InetAddress, port: Int, local: InetAddress, localPort: Int) = Socket(host, port, local, localPort)
        }
        val client = OkHttpClient.Builder().proxy(Proxy.NO_PROXY).socketFactory(factory)
            .dns { listOf(InetAddress.getByName("::1"), InetAddress.getByName("127.0.0.1")) }
            .fastFallback(true).retryOnConnectionFailure(false).build()
        val started = System.nanoTime()
        val ipv4 = MusicHttpExchange.execute("GET", "http://fallback.fixture.test:${server.address.port}/cookies",
            emptyMap(), byteArrayOf(), 3000, false, 10000, MusicHttpExchange.Task(), client)
        check(ipv4.status == 200 && (System.nanoTime() - started) / 1000000 < 1500)
        check(ipv6Started.get() > 0 && ipv6Closed.get() > 0); passed++
        println("$passed native system HTTP scenarios passed")
    } finally { server.stop(0); executor.shutdownNow() }
}
