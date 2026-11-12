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
    private var preparation: QishuiOfficialAudioPreparation? = null
    private var executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val requests = ConcurrentHashMap<String, AtomicBoolean>()
    @Volatile private var attached = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        preparation = QishuiOfficialAudioPreparation(File(binding.applicationContext.cacheDir, "qishui_official_audio"))
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
                    result.error("format", "Invalid private media operation",
                        QishuiAudioFailure(QishuiAudioStep.cachePath, QishuiAudioReason.operationInvalid, "format").details())
                    return@setMethodCallHandler
                }
                val cancelled = AtomicBoolean(false)
                if (id != null && requests.putIfAbsent(id, cancelled) != null) {
                    result.error("format", "Duplicate private media operation",
                        QishuiAudioFailure(QishuiAudioStep.cachePath, QishuiAudioReason.operationInvalid, "format").details())
                    return@setMethodCallHandler
                }
                executor.execute {
                    var output: File? = null
                    var step = QishuiAudioStep.cachePath
                    try {
                        val preparer = preparation ?: throw IllegalStateException("detached")
                        val value = if (call.method == "prepare") {
                            val path = preparer.prepare(id, call.argument<String>("source"),
                                call.argument<String>("output"), call.argument<Boolean>("encrypted") == true,
                                call.argument<String>("playAuth") ?: "") { cancelled.get() || !attached }
                            output = preparer.privateFile(path)
                            mapOf("path" to path)
                        } else {
                            val file = preparer.privateFile(call.argument<String>("path"))
                            step = QishuiAudioStep.metadataRead
                            inspect(file)
                        }
                        main.post {
                            if (cancelled.get() || !attached) {
                                runCatching { output?.delete() }
                                result.error("cancelled", "Private media operation cancelled", null)
                            } else result.success(value)
                        }
                    } catch (_: CancellationException) {
                        runCatching { output?.delete() }
                        main.post { result.error("cancelled", "Private media operation cancelled", null) }
                    } catch (error: Throwable) {
                        // Raw decoder/platform errors can contain paths or
                        // media authorization; expose a fixed category only.
                        runCatching { output?.delete() }
                        val failure = QishuiAudioFailure.classify(error, step)
                        main.post { result.error("format", "Official media validation failed", failure.details()) }
                    } finally {
                        if (id != null) requests.remove(id, cancelled)
                    }
                }
            }
        }
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
    }
}
