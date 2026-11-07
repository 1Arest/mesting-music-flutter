package com.mesting.music

import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CancellationException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Engine-owned, private-cache-only bridge. No network, account or key store. */
class QishuiOfficialAudioPlugin : FlutterPlugin {
    private var channel: MethodChannel? = null
    private var root: File? = null
    private var executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val requests = ConcurrentHashMap<String, AtomicBoolean>()
    @Volatile private var attached = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        root = File(binding.applicationContext.cacheDir, "qishui_official_audio").canonicalFile
        attached = true
        if (executor.isShutdown) executor = Executors.newSingleThreadExecutor()
        channel = MethodChannel(binding.binaryMessenger, "com.mesting.music/qishui_official_audio").also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method == "cancel") {
                    requests[call.argument<String>("id")]?.set(true)
                    result.success(null)
                    return@setMethodCallHandler
                }
                if (call.method != "prepare" && call.method != "inspect") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val id = if (call.method == "prepare") call.argument<String>("id") else null
                if (id != null && !ID.matches(id)) {
                    result.error("format", "Invalid private media operation", null)
                    return@setMethodCallHandler
                }
                val cancelled = AtomicBoolean(false)
                if (id != null && requests.putIfAbsent(id, cancelled) != null) {
                    result.error("format", "Duplicate private media operation", null)
                    return@setMethodCallHandler
                }
                executor.execute {
                    var output: File? = null
                    try {
                        val value = if (call.method == "prepare") {
                            require(id != null) { "operation_id" }
                            val source = privateFile(call.argument<String>("source"), "$id.source")
                            output = privateFile(call.argument<String>("output"), "$id.m4a", requireExists = false)
                            require(!output!!.exists()) { "output_exists" }
                            require(source.length() in 1..QishuiOfficialAudioDecrypt.MAX_FILE_BYTES.toLong()) { "media_size" }
                            val encoded = source.readBytes()
                            val plain = if (call.argument<Boolean>("encrypted") == true) {
                                QishuiOfficialAudioDecrypt.decryptAudio(encoded, call.argument<String>("playAuth") ?: "") {
                                    cancelled.get() || !attached
                                }
                            } else encoded
                            if (cancelled.get() || !attached) throw CancellationException("cancelled")
                            // The caller publishes only after a separate extractor
                            // inspection and a final account/selection check.
                            output!!.outputStream().use { it.write(plain); it.flush() }
                            if (cancelled.get() || !attached) throw CancellationException("cancelled")
                            mapOf("path" to output!!.path)
                        } else {
                            inspect(privateFile(call.argument<String>("path")))
                        }
                        main.post {
                            if (cancelled.get() || !attached) {
                                output?.delete()
                                result.error("cancelled", "Private media operation cancelled", null)
                            } else result.success(value)
                        }
                    } catch (_: CancellationException) {
                        output?.delete()
                        main.post { result.error("cancelled", "Private media operation cancelled", null) }
                    } catch (_: Throwable) {
                        // Raw decoder/platform errors can contain paths or
                        // media authorization; expose a fixed category only.
                        output?.delete()
                        main.post { result.error("format", "Official media validation failed", null) }
                    } finally {
                        if (id != null) requests.remove(id, cancelled)
                    }
                }
            }
        }
    }

    private fun privateFile(path: String?, exactName: String? = null, requireExists: Boolean = true): File {
        require(path != null) { "path_missing" }
        val file = File(path)
        val parent = root ?: throw IllegalStateException("detached")
        require(file.isAbsolute && file.canonicalFile.parentFile == parent && file.absoluteFile == file.canonicalFile) {
            "path_outside_private_cache"
        }
        require(if (exactName == null) OUTPUT.matches(file.name) else file.name == exactName) { "path_name" }
        if (requireExists) require(file.isFile) { "path_missing" }
        return file
    }

    private fun inspect(file: File): Map<String, Any> {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(file.path)
            var audio: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val candidate = extractor.getTrackFormat(i)
                if (candidate.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    require(audio == null) { "multiple_audio_tracks" }
                    audio = candidate
                }
            }
            val format = audio ?: throw IllegalArgumentException("audio_track_missing")
            val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
            val duration = format.getLong(MediaFormat.KEY_DURATION)
            require(duration > 0) { "audio_duration_missing" }
            val type = when (mime) {
                "audio/mp4a-latm", "audio/alac" -> "m4a"
                "audio/flac" -> "flac"
                "audio/mpeg" -> "mp3"
                else -> throw IllegalArgumentException("audio_codec")
            }
            val bitrate = if (format.containsKey(MediaFormat.KEY_BIT_RATE)) {
                format.getInteger(MediaFormat.KEY_BIT_RATE).toLong()
            } else file.length() * 8_000_000L / duration
            return mapOf("durationUs" to duration, "format" to type, "bitrate" to bitrate, "bytes" to file.length())
        } finally {
            extractor.release()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = false
        requests.values.forEach { it.set(true) }
        executor.shutdownNow()
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private companion object {
        val ID = Regex("^[0-9a-f]{32}$")
        val OUTPUT = Regex("^[0-9a-f]{32}\\.m4a$")
    }
}
