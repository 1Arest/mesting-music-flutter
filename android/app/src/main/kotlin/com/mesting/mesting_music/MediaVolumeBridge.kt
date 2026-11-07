package com.mesting.music

import android.content.Context
import android.database.ContentObserver
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/** A lifecycle-scoped STREAM_MUSIC bridge shared by all five player views. */
class MediaVolumeBridge(private val context: Context, messenger: BinaryMessenger) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val methods = MethodChannel(messenger, "com.mesting.music/media_volume")
    private val events = EventChannel(messenger, "com.mesting.music/media_volume_events")
    private var sink: EventChannel.EventSink? = null
    private var observing = false
    private var lastPublished: Double? = null
    private fun publish() {
        val current = read()
        // Settings.System also changes for unrelated preferences. Only media
        // volume changes cross the Flutter boundary and invalidate its UI.
        if (lastPublished != current) {
            lastPublished = current
            sink?.success(current)
        }
    }
    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) { publish() }
    }

    private fun read(): Double {
        val maximum = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        return audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / maximum
    }

    init {
        methods.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getVolume" -> result.success(read())
                    "setVolume" -> {
                        val value = call.argument<Number>("value")?.toDouble()?.coerceIn(0.0, 1.0) ?: read()
                        val maximum = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        // No system volume popup: the visible slider already provides feedback.
                        val target = (value * maximum).roundToInt()
                        if (audio.getStreamVolume(AudioManager.STREAM_MUSIC) != target) {
                            audio.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
                        }
                        result.success(read())
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) { result.error("media_volume", error.message, null) }
        }
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
                sink = eventSink
                if (!observing) {
                    context.contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, observer)
                    observing = true
                }
                lastPublished = null
                publish()
            }
            override fun onCancel(arguments: Any?) { stopObserving() }
        })
    }

    private fun stopObserving() {
        sink = null
        if (observing) context.contentResolver.unregisterContentObserver(observer)
        observing = false
    }

    fun dispose() {
        stopObserving()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }
}
