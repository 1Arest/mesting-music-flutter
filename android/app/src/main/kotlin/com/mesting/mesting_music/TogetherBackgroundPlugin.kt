package com.mesting.music

import android.app.ActivityManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Owned by the audio FlutterEngine, not an Activity or a player page. Reuses
 * the existing media foreground service; never creates a second notification,
 * requests background location, or keeps an ended room awake. */
class TogetherBackgroundPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private val handler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var application: Context? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var lease: String? = null
    private var revision = -1L
    private var enabled = false
    private var inFlight = false
    private val pulse = object : Runnable {
        override fun run() {
            if (!enabled) return
            // audio_service already keeps paused playback in the foreground.
            // This bounded lease also covers network/source preparation gaps.
            if (!inFlight) {
                if (hasMediaService()) acquire() else release()
                inFlight = true
                val sentLease = lease
                channel?.invokeMethod("poll", sentLease, object : MethodChannel.Result {
                    override fun success(result: Any?) { finished(sentLease) }
                    override fun error(code: String, message: String?, details: Any?) { finished(sentLease) }
                    override fun notImplemented() { finished(sentLease) }
                })
            }
            handler.postDelayed(this, 5_000)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        application = binding.applicationContext
        wakeLock = (binding.applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MestingMusic:together-sync")
            .apply { setReferenceCounted(false) }
        channel = MethodChannel(binding.binaryMessenger, "com.mesting.music/together_background")
            .also { it.setMethodCallHandler(this) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "configure") { result.notImplemented(); return }
        val nextRevision = call.argument<Number>("revision")?.toLong() ?: -1
        if (nextRevision >= revision) {
            revision = nextRevision
            lease = call.argument<String>("lease")
            enabled = call.argument<Boolean>("active") == true &&
                call.argument<Boolean>("background") == true
            handler.removeCallbacks(pulse)
            inFlight = false
            if (enabled) handler.post(pulse) else release()
        }
        result.success(null)
    }

    private fun finished(sentLease: String?) {
        if (sentLease == lease) inFlight = false
    }

    @Suppress("DEPRECATION")
    private fun hasMediaService(): Boolean {
        val manager = application?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        return runCatching {
            // Android O+ exposes this application's own services only.
            manager?.getRunningServices(32)?.any {
                it.service.className == "com.ryanheise.audioservice.AudioService" && it.foreground
            } == true
        }.getOrDefault(false)
    }

    private fun acquire() {
        // Timeout is a final bound if the engine cannot acknowledge a pulse.
        // Renew only while the active room and existing foreground media owner
        // remain valid. No wake lock is held for ordinary playback or browsing.
        runCatching { wakeLock?.acquire(90_000) }
    }

    private fun release() {
        runCatching { if (wakeLock?.isHeld == true) wakeLock?.release() }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        enabled = false
        handler.removeCallbacks(pulse)
        channel?.setMethodCallHandler(null)
        channel = null
        release()
        wakeLock = null
        application = null
    }
}
