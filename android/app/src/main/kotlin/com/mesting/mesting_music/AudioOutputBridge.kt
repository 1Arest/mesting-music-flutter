package com.mesting.music

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaRouter
import android.media.MediaRouter2
import android.media.MediaRoute2Info
import android.media.RouteDiscoveryPreference
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Read the SYSTEM'S selected music route, not the first paired Bluetooth
 * device. This bridge neither scans Bluetooth nor creates an audio player. */
class AudioOutputBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val legacy = activity.getSystemService(Context.MEDIA_ROUTER_SERVICE) as MediaRouter
    private val methods = MethodChannel(messenger, "com.mesting.music/audio_output")
    private val events = EventChannel(messenger, "com.mesting.music/audio_output_events")
    private var sink: EventChannel.EventSink? = null
    private var observing = false
    private var modern: ModernRoutes? = null
    private val main = Handler(Looper.getMainLooper())
    // The Beta music player owns its AudioTrack. Stable keeps its established
    // system-controller path, independent of the custom Beta picker.
    private val playerRoutes = if (activity.packageName.endsWith(".beta"))
        MusicPlayerOutputRoutes(activity) { publish() } else null
    private var transferId: String? = null
    private var transferResult: MethodChannel.Result? = null
    private var transferTimeout: Runnable? = null
    private val callback = object : MediaRouter.SimpleCallback() {
        override fun onRouteSelected(router: MediaRouter, type: Int, route: MediaRouter.RouteInfo) = publish()
        override fun onRouteChanged(router: MediaRouter, route: MediaRouter.RouteInfo) = publish()
    }
    private val devices = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) = publish()
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = publish()
    }

    init {
        methods.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "current" -> result.success(read())
                    "routes" -> result.success(read())
                    "transfer" -> {
                        val id = call.argument<String>("id")
                        if (playerRoutes != null) {
                            playerRoutes.transfer(id, result)
                        } else if (Build.VERSION.SDK_INT < 30 || id.isNullOrBlank()) {
                            result.success(false)
                        } else if (transferResult != null) {
                            result.error("audio_output_busy", "设备正在切换，请稍候", null)
                        } else {
                            val router = MediaRouter2.getInstance(activity)
                            // Only public transferable routes are actionable.
                            // A paired Bluetooth device is not proof of a route.
                            val route = router.systemController.transferableRoutes.firstOrNull { it.id == id }
                            if (route == null) result.success(false) else {
                                if (modern == null) modern = ModernRoutes()
                                transferId = id
                                transferResult = result
                                transferTimeout = Runnable { finishTransfer(false) }.also { main.postDelayed(it, 8000) }
                                try { router.transferTo(route) }
                                catch (error: Exception) { finishTransfer(false) }
                            }
                        }
                    }
                    "choose" -> {
                        // The public system picker starts at Android 14. Older
                        // phones use their Bluetooth settings instead of hidden
                        // vendor intents or a picker claiming fake transfers.
                        val shown = Build.VERSION.SDK_INT >= 34 && runCatching {
                            MediaRouter2.getInstance(activity).showSystemOutputSwitcher()
                        }.getOrDefault(false)
                        if (!shown) activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) { result.error("audio_output", error.message, null) }
        }
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
                sink = eventSink
                if (!observing) {
                    observing = true
                    // No discovery flags: observe connected routes without
                    // requesting active scans or depending on AndroidX flags.
                    legacy.addCallback(MediaRouter.ROUTE_TYPE_LIVE_AUDIO, callback)
                    audio.registerAudioDeviceCallback(devices, Handler(Looper.getMainLooper()))
                    if (Build.VERSION.SDK_INT >= 30 && modern == null) modern = ModernRoutes()
                }
                publish()
            }
            override fun onCancel(arguments: Any?) = stop()
        })
    }

    @Suppress("DEPRECATION")
    private fun read(): Map<String, Any> {
        playerRoutes?.let { return it.read() }
        if (Build.VERSION.SDK_INT >= 30) {
            // A system controller includes Bluetooth, wired and local outputs
            // and supplies user/OEM names without BLUETOOTH_CONNECT access.
            val route = MediaRouter2.getInstance(activity).systemController.selectedRoutes.firstOrNull()
            if (route != null) {
                val controller = MediaRouter2.getInstance(activity).systemController
                // Some OEMs restrict route enumeration. Retain the confirmed
                // current-device metadata even when no transferable list is exposed.
                val transferable = runCatching { controller.transferableRoutes }.getOrDefault(emptyList())
                val routes = (listOf(route) + transferable).distinctBy { it.id }.map {
                    mapOf("id" to it.id, "name" to it.name.toString(), "kind" to kind(it.type),
                        "selected" to (it.id == route.id),
                        "selectable" to (it.id != route.id && transferable.any { candidate -> candidate.id == it.id }))
                }
                return mapOf("id" to route.id, "name" to route.name.toString(), "kind" to kind(route.type),
                    "available" to true, "routes" to routes)
            }
        }
        val selected = legacy.getSelectedRoute(MediaRouter.ROUTE_TYPE_LIVE_AUDIO)
        val outputs = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val wired = if (audio.isWiredHeadsetOn) outputs.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET } else null
        val headphone = selected.deviceType == MediaRouter.RouteInfo.DEVICE_TYPE_BLUETOOTH || wired != null
        val name = wired?.productName?.toString()?.takeIf { it.isNotBlank() }
            ?: selected.name?.toString()?.takeIf { it.isNotBlank() } ?: "本机扬声器"
        return mapOf("name" to name, "kind" to if (headphone) "headphones" else "speaker", "available" to true)
    }

    private fun kind(type: Int): String = when (type) {
        MediaRoute2Info.TYPE_WIRED_HEADSET, MediaRoute2Info.TYPE_WIRED_HEADPHONES,
        MediaRoute2Info.TYPE_BLUETOOTH_A2DP, MediaRoute2Info.TYPE_USB_HEADSET,
        MediaRoute2Info.TYPE_BLE_HEADSET, MediaRoute2Info.TYPE_HEARING_AID -> "headphones"
        else -> "speaker"
    }
    private fun publish() {
        // OEM route services may briefly disappear during a Bluetooth change.
        // Keep the last confirmed metadata; a foreground probe can recover.
        runCatching { read() }.onSuccess {
            sink?.success(it)
            if (transferId != null && it["id"] == transferId) finishTransfer(true)
        }
    }

    /** Complete only on a confirmed selection or bounded failure, never on tap. */
    private fun finishTransfer(success: Boolean) {
        val result = transferResult ?: return
        transferTimeout?.let { main.removeCallbacks(it) }
        transferTimeout = null
        transferResult = null
        transferId = null
        result.success(success)
    }

    /** Keep API-30 classes out of the legacy lifecycle path. */
    @android.annotation.TargetApi(30)
    private inner class ModernRoutes {
        private val router = MediaRouter2.getInstance(activity)
        private val routes = object : MediaRouter2.RouteCallback() {
            override fun onRoutesAdded(routes: MutableList<MediaRoute2Info>) = publish()
            override fun onRoutesChanged(routes: MutableList<MediaRoute2Info>) = publish()
            override fun onRoutesRemoved(routes: MutableList<MediaRoute2Info>) = publish()
        }
        private val controller = object : MediaRouter2.ControllerCallback() {
            override fun onControllerUpdated(controller: MediaRouter2.RoutingController) = publish()
        }
        private val transfers = object : MediaRouter2.TransferCallback() {
            override fun onTransfer(oldController: MediaRouter2.RoutingController, newController: MediaRouter2.RoutingController) = publish()
            override fun onTransferFailure(route: MediaRoute2Info) {
                if (route.id == transferId) finishTransfer(false)
                publish()
            }
        }
        init {
            router.registerRouteCallback(activity.mainExecutor, routes,
                RouteDiscoveryPreference.Builder(listOf(MediaRoute2Info.FEATURE_LIVE_AUDIO), false).build())
            router.registerControllerCallback(activity.mainExecutor, controller)
            router.registerTransferCallback(activity.mainExecutor, transfers)
        }
        fun dispose() {
            router.unregisterRouteCallback(routes)
            router.unregisterControllerCallback(controller)
            router.unregisterTransferCallback(transfers)
        }
    }
    private fun stop() {
        finishTransfer(false)
        sink = null
        if (observing) {
            legacy.removeCallback(callback)
            audio.unregisterAudioDeviceCallback(devices)
            modern?.dispose()
        }
        modern = null
        observing = false
    }
    fun dispose() { stop(); playerRoutes?.dispose(); methods.setMethodCallHandler(null); events.setStreamHandler(null) }
}
