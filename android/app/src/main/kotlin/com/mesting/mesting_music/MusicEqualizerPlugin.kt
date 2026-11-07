package com.mesting.music

import android.media.audiofx.Equalizer
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * App-scoped effects on the existing music session. No global session 0 and no
 * second player. Lifecycle/timeout design follows md3Music v6.1.0 EqualizerPlugin
 * (AGPL, attribution in third_party/md3music/MESTING-1.0.3-PORTS.md).
 *
 * The plugin belongs to the engine, not the Activity: background audio must
 * retain its effects when Android recreates the visible page. A generation
 * ticket rejects late construction after a route/session change or teardown.
 */
class MusicEqualizerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private var equalizer: Equalizer? = null
    private var sessionId = 0
    private var generation = 0L
    private var detached = true

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detached = false
        channel = MethodChannel(binding.binaryMessenger, "com.mesting.music/equalizer")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detached = true
        release()
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "bind" -> bind((call.argument<Number>("sessionId")?.toInt() ?: 0), result)
            "release" -> { release(); result.success(null) }
            "apply" -> {
                val eq = equalizer
                if (eq == null || call.argument<Number>("sessionId")?.toInt() != sessionId) {
                    result.error("SESSION_CHANGED", "音频会话已变化，请重试", null)
                    return
                }
                try {
                    val requested = call.argument<List<Number>>("levels") ?: emptyList()
                    val range = eq.bandLevelRange
                    require(requested.size == eq.numberOfBands.toInt())
                    val levels = requested.map { it.toInt() }
                    require(levels.all { it in range[0].toInt()..range[1].toInt() })
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val oldLevels = (0 until eq.numberOfBands.toInt()).map { eq.getBandLevel(it.toShort()) }
                    val oldEnabled = eq.enabled
                    try {
                        levels.forEachIndexed { band, level -> eq.setBandLevel(band.toShort(), level.toShort()) }
                        eq.enabled = enabled
                        check(eq.enabled == enabled)
                    } catch (error: Exception) {
                        // Preserve the prior audible state on a partial device
                        // rejection; Dart never saves an unsuccessful choice.
                        runCatching {
                            oldLevels.forEachIndexed { band, level -> eq.setBandLevel(band.toShort(), level) }
                            eq.enabled = oldEnabled
                        }
                        throw error
                    }
                    result.success(info(eq))
                } catch (_: Exception) {
                    result.error("APPLY_FAILED", "设备未能应用音效，请重试或关闭均衡器", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun bind(id: Int, result: MethodChannel.Result) {
        if (id <= 0 || detached) {
            result.error("NO_SESSION", "请先播放一首歌曲", null)
            return
        }
        if (id == sessionId && equalizer != null) {
            try { result.success(info(equalizer!!)) }
            catch (_: Exception) { result.error("DEVICE_UNAVAILABLE", "设备均衡器暂不可用", null) }
            return
        }
        release()
        val ticket = generation
        val done = AtomicBoolean(false)
        val timeout = Runnable {
            if (done.compareAndSet(false, true)) result.error("BIND_TIMEOUT", "设备均衡器初始化超时，请重试", null)
        }
        main.postDelayed(timeout, 4000)
        Thread({
            var created: Equalizer? = null
            var snapshot: Map<String, Any>? = null
            try {
                created = Equalizer(0, id)
                snapshot = info(created)
            } catch (_: Exception) { /* Return a bounded user-facing error. */ }
            val candidate = created
            val ready = snapshot
            main.post {
                main.removeCallbacks(timeout)
                if (!done.compareAndSet(false, true)) {
                    runCatching { candidate?.release() }
                } else if (detached || generation != ticket || candidate == null || ready == null) {
                    runCatching { candidate?.release() }
                    result.error("DEVICE_UNAVAILABLE", "音频会话已变化或设备不支持均衡器", null)
                } else {
                    equalizer = candidate
                    sessionId = id
                    result.success(ready)
                }
            }
        }, "MestingEqualizerInit").apply { isDaemon = true; start() }
    }

    private fun release() {
        generation++
        val previous = equalizer
        equalizer = null
        sessionId = 0
        runCatching { previous?.release() }
    }

    private fun info(eq: Equalizer): Map<String, Any> {
        val count = eq.numberOfBands.toInt()
        require(count in 1..32)
        val range = eq.bandLevelRange
        return mapOf(
            "frequencies" to (0 until count).map { eq.getCenterFreq(it.toShort()) },
            "levels" to (0 until count).map { eq.getBandLevel(it.toShort()).toInt() },
            "minimum" to range[0].toInt(), "maximum" to range[1].toInt(),
            "enabled" to eq.enabled,
        )
    }
}
