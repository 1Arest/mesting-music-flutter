package com.mesting.music

import android.app.Activity
import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.HapticFeedbackConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Short UI feedback only. No media focus, audio session, background vibration,
 * or bypass of the system haptics preference belongs to this bridge. */
class HapticFeedbackBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.mesting.music/haptics")
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "emit") result.notImplemented()
            else {
                val strength = (call.argument<Number>("strength")?.toInt() ?: 0).coerceIn(0, 2)
                result.success(emit(call.argument<String>("kind") ?: "selection", strength))
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun emit(kind: String, strength: Int): Boolean {
        val view = activity.window.decorView
        if (activity.isFinishing || !view.isHapticFeedbackEnabled ||
            Settings.System.getInt(activity.contentResolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) == 0) return false
        return try {
            val vibrator = if (Build.VERSION.SDK_INT >= 31)
                activity.getSystemService(VibratorManager::class.java)?.defaultVibrator
                else activity.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (vibrator?.hasVibrator() != true) return false
            if (Build.VERSION.SDK_INT >= 26 && vibrator.hasAmplitudeControl()) {
                val amplitude = intArrayOf(45, 100, 180)[strength]
                val pulse = longArrayOf(8, 12, 16)[strength]
                val effect = if (kind == "success" || kind == "warning")
                    VibrationEffect.createWaveform(longArrayOf(0, pulse, 35, pulse), intArrayOf(0, amplitude, 0, amplitude), -1)
                    else VibrationEffect.createOneShot(pulse, amplitude)
                val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
                vibrator.vibrate(effect, attributes)
                true
            } else {
                // Devices without amplitude control retain the system pattern
                // and its accessibility/user preference handling.
                view.performHapticFeedback(when {
                    kind == "selection" -> HapticFeedbackConstants.KEYBOARD_TAP
                    strength == 2 -> HapticFeedbackConstants.LONG_PRESS
                    else -> HapticFeedbackConstants.CONTEXT_CLICK
                })
            }
        } catch (_: SecurityException) { false }
    }

    fun dispose() { channel.setMethodCallHandler(null) }
}
