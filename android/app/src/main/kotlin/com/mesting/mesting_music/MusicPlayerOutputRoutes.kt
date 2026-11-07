package com.mesting.music

import android.app.Activity
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaRouter2
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.ryanheise.just_audio.MestingAudioOutput
import io.flutter.plugin.common.MethodChannel

/** The app chooses its own music output. Android keeps Bluetooth connections
 * and global media routing; selecting 本机 never disconnects the headphones. */
class MusicPlayerOutputRoutes(private val activity: Activity, private val changed: () -> Unit) {
    private val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())
    private val owner = "mesting-music"
    private var result: MethodChannel.Result? = null
    private var target: AudioDeviceInfo? = null
    private var previousPreference: AudioDeviceInfo? = null
    private var deadline = 0L
    private val check = object : Runnable {
        override fun run() {
            val desired = target ?: return
            val current = MestingAudioOutput.currentDevice(owner)
            if (current?.id == desired.id) finish(true)
            else if (!MestingAudioOutput.isPlaying(owner)) finish(true)
            else if (android.os.SystemClock.uptimeMillis() >= deadline) {
                MestingAudioOutput.requestDevice(owner, previousPreference)
                finish(false)
            } else main.postDelayed(this, 100)
        }
    }

    init { MestingAudioOutput.observe(owner) { changed() } }

    private fun local(device: AudioDeviceInfo) = device.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
    private fun headphones(device: AudioDeviceInfo) = device.type in setOf(
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_HEARING_AID)
    private fun devices() = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).filter {
        // Only connected media sinks, never paired/disconnected devices, SCO
        // communication routes or virtual submix/capture endpoints.
        local(it) || headphones(it) || it.type in setOf(
            AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_ACCESSORY,
            AudioDeviceInfo.TYPE_BLE_SPEAKER,
            AudioDeviceInfo.TYPE_HDMI, AudioDeviceInfo.TYPE_HDMI_ARC,
            AudioDeviceInfo.TYPE_LINE_ANALOG, AudioDeviceInfo.TYPE_LINE_DIGITAL)
    }
    private fun key(device: AudioDeviceInfo) = "device:${device.id}"
    private fun name(device: AudioDeviceInfo) = if (local(device)) "本机" else
        device.productName?.toString()?.takeIf { it.isNotBlank() } ?: "音频设备"

    fun read(): Map<String, Any> {
        val outputs = devices()
        var preferred = MestingAudioOutput.preferredDevice(owner)
        if (preferred != null && outputs.none { it.id == preferred!!.id }) {
            // Unplugged outputs must not resurrect a saved routing preference.
            MestingAudioOutput.requestDevice(owner, null)
            preferred = null
        }
        val actual = MestingAudioOutput.currentDevice(owner)?.let { routed -> outputs.find { it.id == routed.id } }
        // Before a track exists, show the OS default; a paused custom request
        // is explicitly marked pending instead of presented as successful audio.
        val systemType = if (Build.VERSION.SDK_INT >= 30) runCatching {
            MediaRouter2.getInstance(activity).systemController.selectedRoutes.firstOrNull()?.type
        }.getOrNull() else null
        val current = actual ?: outputs.find { it.type == systemType } ?: outputs.find(::local) ?: outputs.firstOrNull()
        val pending = preferred?.takeIf { actual?.id != it.id }
        val ordered = outputs.sortedBy { if (local(it)) 0 else 1 }
        return mapOf(
            "id" to (current?.let(::key) ?: ""),
            "name" to (current?.let(::name) ?: "本机"),
            "kind" to (if (current == null || local(current)) "phone" else if (headphones(current)) "headphones" else "speaker"),
            "available" to outputs.isNotEmpty(),
            "pendingId" to (pending?.let(::key) ?: ""),
            "routes" to ordered.map { device -> mapOf(
                "id" to key(device), "name" to name(device),
                "kind" to (if (local(device)) "phone" else if (headphones(device)) "headphones" else "speaker"),
                "selected" to (device.id == current?.id && pending?.id != device.id),
                "selectable" to (device.id != actual?.id || pending != null)) })
    }

    fun transfer(id: String?, reply: MethodChannel.Result) {
        if (result != null) { reply.error("audio_output_busy", "设备正在切换，请稍候", null); return }
        val device = devices().firstOrNull { key(it) == id }
        if (device == null) { reply.success(false); return }
        previousPreference = MestingAudioOutput.preferredDevice(owner)
        if (!MestingAudioOutput.requestDevice(owner, device)) { reply.success(false); return }
        target = device
        result = reply
        deadline = android.os.SystemClock.uptimeMillis() + 8000
        main.post(check)
    }

    private fun finish(accepted: Boolean) {
        val reply = result ?: return
        main.removeCallbacks(check)
        target = null
        result = null
        previousPreference = null
        changed()
        reply.success(accepted)
    }

    fun dispose() { finish(false); MestingAudioOutput.unobserve(owner) }
}
