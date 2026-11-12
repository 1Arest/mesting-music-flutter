package com.mesting.music

import android.app.ActivityManager
import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import com.ryanheise.audioservice.MestingTogetherMediaLease

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
        private var diagnosticLogging = false
        private var loggingRevision = -1L
        val scheduler = TogetherPulseScheduler(eventSink = { event ->
            if (diagnosticLogging) {
                Log.i("MestingTogetherSync", JSONObject(mapOf("source" to "native") + event).toString())
            }
        })
        val wakeLock = (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MestingMusic:together-sync")
            .apply { setReferenceCounted(false) }
        @Volatile var closed = false
        private var active = false
        private var mediaPresent: Boolean? = null
        init {
            queue.post { scheduler.record(TogetherPulseScheduler.Phase.engineAttached, SystemClock.elapsedRealtime()) }
        }
        private fun current() = !closed && owner === this
        private val pulse = object : Runnable {
            override fun run() {
                if (!current() || !active) return
                val media = hasMediaService()
                if (mediaPresent != media) {
                    mediaPresent = media
                    scheduler.record(
                        if (media) TogetherPulseScheduler.Phase.mediaServicePresent
                        else TogetherPulseScheduler.Phase.mediaServiceMissing,
                        SystemClock.elapsedRealtime(),
                    )
                }
                if (media) acquire() else release()
                scheduler.poll(SystemClock.elapsedRealtime())?.let { request ->
                    main.post {
                        if (!current() || !request.deliverable) {
                            recordDelivery(TogetherPulseScheduler.Phase.pulseUndeliverable, request)
                            return@post
                        }
                        // A cold restored, paused room has an AudioService
                        // instance but no foreground playback yet. Reuse that
                        // exact service/notification without inventing audio
                        // or changing the real play/pause state. The lease is
                        // revoked on every stop/expiry/engine replacement.
                        when (MestingTogetherMediaLease.acquire(context, this@EngineWorker)) {
                            TogetherMediaLeaseCoordinator.Outcome.acquired ->
                                recordDelivery(TogetherPulseScheduler.Phase.foregroundLeaseAcquired, request)
                            TogetherMediaLeaseCoordinator.Outcome.rejected ->
                                recordDelivery(TogetherPulseScheduler.Phase.foregroundLeaseRejected, request)
                            else -> Unit
                        }
                        recordDelivery(TogetherPulseScheduler.Phase.pulseSent, request)
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
                    releaseMediaLease()
                    return
                }
                // A missing Dart reply cannot strand the in-flight flag.
                queue.postDelayed(this, 1_000)
            }
        }

        fun configure(revision: Long, lease: String?, enabled: Boolean, logEvents: Boolean, result: MethodChannel.Result) {
            queue.post {
                // The default-off candidate flag uses the existing channel;
                // a late older configuration cannot change the new owner.
                if (current() && revision >= loggingRevision) {
                    loggingRevision = revision
                    diagnosticLogging = logEvents
                }
                val accepted = current() &&
                    scheduler.configure(revision, lease, enabled, SystemClock.elapsedRealtime())
                if (accepted) {
                    active = enabled
                    queue.removeCallbacks(pulse)
                    if (active) queue.post(pulse) else {
                        release()
                        releaseMediaLease()
                    }
                }
                main.post { result.success(mapOf("accepted" to accepted, "revision" to revision)) }
            }
        }

        fun diagnosticSnapshot(): Map<String, Any> =
            scheduler.diagnosticSnapshot() + mapOf("loggingEnabled" to diagnosticLogging)

        private fun finish(request: TogetherPulseScheduler.Request, accepted: Boolean) {
            queue.post {
                if (current()) scheduler.finish(request, accepted, SystemClock.elapsedRealtime())
            }
        }

        private fun recordDelivery(phase: TogetherPulseScheduler.Phase, request: TogetherPulseScheduler.Request) {
            // Capture the actual main-thread send timestamp, then serialize
            // journal writes on the worker. A scheduled-but-unsent request is
            // distinct from a send that Dart has not yet acknowledged.
            val at = SystemClock.elapsedRealtime()
            queue.post { if (current()) scheduler.record(phase, at, request.id) }
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
            runCatching {
                if (!wakeLock.isHeld) {
                    wakeLock.acquire(90_000)
                    scheduler.record(TogetherPulseScheduler.Phase.wakeAcquired, SystemClock.elapsedRealtime())
                }
            }
        }
        private fun release() {
            runCatching {
                if (wakeLock.isHeld) {
                    wakeLock.release()
                    scheduler.record(TogetherPulseScheduler.Phase.wakeReleased, SystemClock.elapsedRealtime())
                }
            }
        }

        private fun releaseMediaLease() {
            // The coordinator uses identity-based owners. An old engine's
            // delayed teardown cannot remove a newer engine's media lease,
            // and ordinary audio notifications are never withdrawn here.
            main.post { MestingTogetherMediaLease.release(this@EngineWorker) }
        }

        fun close() {
            closed = true
            queue.post {
                active = false
                queue.removeCallbacks(pulse)
                scheduler.stop(SystemClock.elapsedRealtime())
                release()
                releaseMediaLease()
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
            "diagnosticSnapshot" -> current.queue.post {
                val snapshot = current.diagnosticSnapshot()
                main.post { result.success(snapshot) }
            }
            "configure" -> current.configure(
                call.argument<Number>("revision")?.toLong() ?: -1,
                call.argument<String>("lease"),
                call.argument<Boolean>("active") == true &&
                    call.argument<Boolean>("background") == true,
                call.argument<Boolean>("diagnosticLogging") == true,
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
