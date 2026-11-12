package com.mesting.music

import android.content.Context
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.TimeZone

/** Public system/application context only; never reads IMEI, Android ID,
 * installed music accounts, SMS or another app's private installation data.
 * BDInstall identifiers and native security factors are deliberately absent:
 * random numbers are not substitutes for a successful installation handshake.
 */
class QishuiContextPlugin : FlutterPlugin {
    private var channel: MethodChannel? = null
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context: Context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.mesting.music/qishui").also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method != "context") { result.notImplemented(); return@setMethodCallHandler }
                val display = context.resources.displayMetrics
                result.success(mapOf(
                    "device_platform" to "android", "os" to "android",
                    "os_api" to Build.VERSION.SDK_INT.toString(), "os_version" to Build.VERSION.RELEASE,
                    "device_type" to Build.MODEL, "device_brand" to Build.BRAND,
                    "device_model" to Build.MODEL, "language" to Locale.getDefault().language,
                    "resolution" to "${display.heightPixels}*${display.widthPixels}",
                    "dpi" to display.densityDpi.toString(), "package" to context.packageName,
                    "tz_name" to TimeZone.getDefault().id,
                    "tz_offset" to (TimeZone.getDefault().getOffset(System.currentTimeMillis()) / 1000).toString()
                ))
            }
        }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
