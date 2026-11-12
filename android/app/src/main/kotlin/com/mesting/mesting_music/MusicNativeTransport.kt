package com.mesting.music

import androidx.annotation.Keep
import org.json.JSONObject
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import javax.net.ssl.SSLException

/** JNI DTO fields are kept verbatim; payloads stay in memory and are never
 * logged, persisted to a temporary file, or exposed to a global cookie store.
 */
@Keep
class MusicHttpReply(@JvmField val status: Int, @JvmField val body: ByteArray,
    @JvmField val cookies: Array<String>, @JvmField val finalUrl: String,
    @JvmField val location: String?, @JvmField val ssaCode: String?, @JvmField val error: String?)

@Keep
class MusicStreamReply(@JvmField val id: Long, @JvmField val status: Int,
    @JvmField val length: Long, @JvmField val contentType: String?, @JvmField val error: String?)

/** Rust retains signing/encryption/modules; only its finalized HTTP exchange
 * crosses this boundary. Capturing this class during nativeInstall avoids the
 * Android class-loader trap on Rust-created worker threads after cold start.
 */
@Keep
object MusicNativeTransport {
    private var installed = false
    @JvmStatic private external fun nativeInstall(): Boolean
    @Synchronized fun install() {
        if (installed) return
        System.loadLibrary("kugou_server")
        check(nativeInstall())
        installed = true
    }

    private fun family(error: Exception) = when (error) {
        is UnknownHostException -> "dns"
        is SSLException -> "tls"
        is SocketTimeoutException -> "timeout"
        is IllegalArgumentException -> "format"
        else -> "connection"
    }
    private fun headers(json: String): Map<String, String> {
        val source = JSONObject(json)
        return source.keys().asSequence().associateWith { source.getString(it) }
    }

    @JvmStatic fun exchange(method: String, url: String, headersJson: String,
        body: ByteArray, timeoutMs: Long, followRedirects: Boolean): MusicHttpReply {
        return try {
            val reply = MusicHttpExchange.execute(method, url, headers(headersJson), body,
                timeoutMs, followRedirects, 128 * 1024 * 1024, MusicHttpExchange.Task())
            MusicHttpReply(reply.status, reply.body, reply.headers["set-cookie"]?.toTypedArray()
                ?: emptyArray(), reply.finalUrl, reply.headers["location"]?.firstOrNull(),
                reply.headers["ssa-code"]?.firstOrNull(), null)
        } catch (error: Exception) {
            MusicHttpReply(0, byteArrayOf(), emptyArray(), "", null, null, family(error))
        }
    }

    private val streams = ConcurrentHashMap<Long, MusicHttpExchange.Opened>()
    private val sequence = AtomicLong()
    @JvmStatic fun openStream(url: String): MusicStreamReply {
        val task = MusicHttpExchange.Task()
        return try {
            require(streams.size < 16)
            val response = MusicHttpExchange.open("GET", url, emptyMap(), byteArrayOf(),
                true, task)
            val id = sequence.incrementAndGet()
            streams[id] = response
            MusicStreamReply(id, response.status, response.headers["content-length"]?.firstOrNull()
                ?.toLongOrNull() ?: -1L, response.headers["content-type"]?.firstOrNull(), null)
        } catch (error: Exception) {
            task.cancel()
            MusicStreamReply(0, 0, -1, null, family(error))
        }
    }
    @JvmStatic fun readStream(id: Long, size: Int): ByteArray {
        val stream = streams[id] ?: throw java.io.IOException("Stream closed")
        try {
            val buffer = ByteArray(size.coerceIn(1, 65536))
            val read = stream.stream?.read(buffer) ?: -1
            if (read < 0) { closeStream(id); return byteArrayOf() }
            return buffer.copyOf(read)
        } catch (error: Exception) { closeStream(id); throw java.io.IOException("Stream interrupted") }
    }
    @JvmStatic fun closeStream(id: Long) { streams.remove(id)?.close() }
}
