package com.mesting.music

import android.app.ActivityManager
import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** One worker belongs to the existing audio engine, not an Activity. Its
 * monotonic schedule and acknowledgement deadlines run on a HandlerThread;
 * only messenger delivery briefly crosses the platform main thread. No extra
 * service, notification, player or silent audio source is created. */
class TogetherBackgroundPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var owner: EngineWorker? = null
    private var channel: MethodChannel? = null

    private inner class EngineWorker(val context: Context, val messenger: MethodChannel) {
        val thread = HandlerThread("MestingTogetherSync").also { it.start() }
        val queue = Handler(thread.looper)
        val scheduler = TogetherPulseScheduler()
        val wakeLock = (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MestingMusic:together-sync")
            .apply { setReferenceCounted(false) }
        @Volatile var closed = false
        private var active = false
        private fun current() = !closed && owner === this
        private val pulse = object : Runnable {
            override fun run() {
                if (!current() || !active) return
                if (hasMediaService()) acquire() else release()
                scheduler.poll(SystemClock.elapsedRealtime())?.let { request ->
                    main.post {
                        if (!current() || !request.deliverable) return@post
                        messenger.invokeMethod("poll", mapOf(
                            "lease" to request.lease, "request" to request.id,
                        ), object : MethodChannel.Result {
                            override fun success(result: Any?) = finish(request, result == true)
                            override fun error(code: String, message: String?, details: Any?) = finish(request, false)
                            override fun notImplemented() = finish(request, false)
                        })
                    }
                }
                if (!scheduler.isEnabled) {
                    active = false
                    release()
                    return
                }
                // A missing Dart reply cannot strand the in-flight flag.
                queue.postDelayed(this, 1_000)
            }
        }

        fun configure(revision: Long, lease: String?, enabled: Boolean, result: MethodChannel.Result) {
            queue.post {
                val accepted = current() &&
                    scheduler.configure(revision, lease, enabled, SystemClock.elapsedRealtime())
                if (accepted) {
                    active = enabled
                    queue.removeCallbacks(pulse)
                    if (active) queue.post(pulse) else release()
                }
                main.post { result.success(mapOf("accepted" to accepted, "revision" to revision)) }
            }
        }

        private fun finish(request: TogetherPulseScheduler.Request, accepted: Boolean) {
            queue.post {
                if (current()) scheduler.finish(request, accepted, SystemClock.elapsedRealtime())
            }
        }

        @Suppress("DEPRECATION")
        private fun hasMediaService(): Boolean {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            return runCatching {
                manager?.getRunningServices(32)?.any {
                    it.service.className == "com.ryanheise.audioservice.AudioService" && it.foreground
                } == true
            }.getOrDefault(false)
        }

        private fun acquire() {
            // Bounded and renewed only with a valid room/media owner. An
            // unacknowledged engine loses its lease; this is no battery-policy
            // exemption and never runs for ordinary non-Together playback.
            runCatching { if (!wakeLock.isHeld) wakeLock.acquire(90_000) }
        }
        private fun release() {
            runCatching { if (wakeLock.isHeld) wakeLock.release() }
        }

        fun close() {
            closed = true
            queue.post {
                active = false
                queue.removeCallbacks(pulse)
                scheduler.stop()
                release()
                thread.quitSafely()
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = MethodChannel(binding.binaryMessenger, "com.mesting.music/together_background")
        owner?.close()
        owner = EngineWorker(binding.applicationContext, messenger)
        channel = messenger.also { it.setMethodCallHandler(this) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val current = owner
        if (current == null || current.closed) {
            result.error("engine_detached", "Together engine unavailable", null)
            return
        }
        when (call.method) {
            "diagnostics" -> current.queue.post {
                val counts = current.scheduler.diagnostics()
                main.post { result.success(counts) }
            }
            "configure" -> current.configure(
                call.argument<Number>("revision")?.toLong() ?: -1,
                call.argument<String>("lease"),
                call.argument<Boolean>("active") == true &&
                    call.argument<Boolean>("background") == true,
                result,
            )
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        val old = owner
        owner = null
        old?.close()
    }
}
