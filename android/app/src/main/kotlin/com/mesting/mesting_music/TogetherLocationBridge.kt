package com.mesting.music

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** One foreground fix after an explicit UI action. No background permission,
 * history, Wi-Fi identifiers, storage or continuous location subscription.
 */
class TogetherLocationBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "mesting/together_location")
    private val manager = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val handler = Handler(Looper.getMainLooper())
    private var reply: MethodChannel.Result? = null
    private var listener: LocationListener? = null
    private var foreground = true
    private val timeout = Runnable { fail("location_unavailable", "暂时无法定位，请到信号良好的地方重试") }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestFix" -> {
                    if (!foreground) result.error("not_foreground", "请返回应用后重试", null)
                    else if (reply != null) result.error("busy", "正在获取位置", null)
                    else {
                        reply = result
                        if (hasPermission()) locate()
                        else activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.ACCESS_COARSE_LOCATION), REQUEST)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasPermission() = activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED || activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED

    fun permissions(request: Int): Boolean {
        if (request != REQUEST) return false
        if (reply != null) {
            if (hasPermission()) {
                if (foreground) locate() // Otherwise onResume supplies the fix.
            } else fail("permission_denied", "未开启位置权限，仍可继续一起听")
        }
        return true
    }

    @Suppress("DEPRECATION", "MissingPermission")
    private fun locate() {
        if (!foreground || !hasPermission()) { fail("permission_denied", "请允许位置权限后重试"); return }
        try {
            val providers = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
                .filter { manager.isProviderEnabled(it) }
            if (providers.isEmpty()) { fail("location_disabled", "请先开启系统位置服务"); return }
            val fresh = providers.mapNotNull { provider ->
                try { manager.getLastKnownLocation(provider) } catch (_: SecurityException) { null }
            }.filter { valid(it) }.minByOrNull { it.accuracy }
            if (fresh != null) { finish(fresh); return }
            listener = object : LocationListener {
                override fun onLocationChanged(location: Location) { if (valid(location)) finish(location) }
                override fun onProviderEnabled(provider: String) {}
                override fun onProviderDisabled(provider: String) {}
                override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            }
            // Approximate-only permission can reject the GPS provider. Try the
            // remaining provider rather than requesting more permission.
            var requested = false
            for (provider in providers) {
                try { manager.requestLocationUpdates(provider, 0L, 0f, listener!!, Looper.getMainLooper()); requested = true }
                catch (_: SecurityException) { /* approximate fix remains valid */ }
            }
            if (!requested) fail("location_unavailable", "当前位置暂不可用，请稍后重试")
            else handler.postDelayed(timeout, 12_000L)
        } catch (_: RuntimeException) { fail("location_unavailable", "当前位置暂不可用，请稍后重试") }
    }

    private fun valid(location: Location): Boolean =
        location.latitude.isFinite() && location.latitude in -90.0..90.0 &&
        location.longitude.isFinite() && location.longitude in -180.0..180.0 &&
        SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos in 0..120_000_000_000L &&
        location.hasAccuracy() && location.accuracy in 0f..50_000f

    private fun finish(location: Location) {
        val pending = reply ?: return
        reply = null
        clean()
        pending.success(mapOf("latitude" to location.latitude, "longitude" to location.longitude,
            "accuracyMeters" to location.accuracy.toDouble()))
    }
    private fun fail(code: String, message: String) {
        val pending = reply
        reply = null
        clean()
        pending?.error(code, message, null)
    }
    private fun clean() {
        handler.removeCallbacks(timeout)
        listener?.let { try { manager.removeUpdates(it) } catch (_: RuntimeException) {} }
        listener = null
    }
    fun foreground(value: Boolean) {
        foreground = value
        if (value && reply != null && listener == null && hasPermission()) locate()
        // Permission dialogs pause the Activity; wait for its permission result.
        if (!value && listener != null) fail("not_foreground", "已停止定位，返回应用后可重试")
    }
    fun dispose() { fail("cancelled", "定位已取消"); channel.setMethodCallHandler(null) }
    companion object { private const val REQUEST = 17443 }
}
