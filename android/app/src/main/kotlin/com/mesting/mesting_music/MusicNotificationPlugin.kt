package com.mesting.music

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** Shared by the activity and headless job. UI capabilities stay ActivityAware;
 * a background engine cannot request permission or start an activity. */
class MusicNotificationPlugin(private val done: (() -> Unit)? = null) : FlutterPlugin,
    MethodChannel.MethodCallHandler, ActivityAware, PluginRegistry.NewIntentListener,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var context: android.content.Context
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private var permissionResult: MethodChannel.Result? = null
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.mesting.music/notifications")
        channel.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        permissionResult?.success(false); permissionResult = null
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "state" -> result.success(MusicNoticeStore.state(context))
                "bind" -> { MusicNoticeStore.bind(context, call.argument<Map<String, String>>("owners") ?: emptyMap()); result.success(null) }
                "invalidate" -> { MusicNoticeStore.invalidate(context, call.argument<String>("platform").orEmpty()); result.success(null) }
                "settings" -> { MusicNoticeStore.settings(context, call.argument<Map<String, Any?>>("values") ?: emptyMap()); result.success(null) }
                "begin" -> result.success(MusicNoticeStore.begin(context))
                "commit" -> result.success(MusicNoticeStore.commit(context, call.arguments as? Map<String, Any?> ?: emptyMap()))
                "release" -> { MusicNoticeStore.release(call.argument<String>("lease")); result.success(null) }
                "error" -> { MusicNoticeStore.error(context, call.argument<String>("platform").orEmpty(), call.argument<String>("feed").orEmpty()); result.success(null) }
                "entry" -> result.success(MusicNoticeStore.entry(context))
                "acknowledge" -> { MusicNoticeStore.acknowledge(context, call.argument<String>("id").orEmpty()); result.success(null) }
                "lastPlatform" -> result.success(MusicNoticeStore.lastPlatform(context, call.argument<String>("platform")))
                "finished" -> { result.success(null); done?.invoke() }
                "permission" -> {
                    val current = activity
                    if (Build.VERSION.SDK_INT < 33 || MusicNoticeStore.permitted(context) || current == null) {
                        result.success(MusicNoticeStore.permitted(context))
                    } else if (permissionResult != null) result.success(false)
                    else { permissionResult = result; current.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 37221) }
                }
                "systemSettings" -> {
                    val current = activity
                    if (current != null) current.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName))
                    result.success(current != null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) { result.error("notice_unavailable", "通知操作暂未完成", null) }
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding; activity = binding.activity
        binding.addOnNewIntentListener(this); binding.addRequestPermissionsResultListener(this)
    }
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() {
        binding?.removeOnNewIntentListener(this); binding?.removeRequestPermissionsResultListener(this)
        binding = null; activity = null
        permissionResult?.success(false); permissionResult = null
    }
    override fun onNewIntent(intent: Intent): Boolean {
        // The entry trampoline already validated and durably queued the action.
        channel.invokeMethod("entryAvailable", null)
        return false
    }
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray): Boolean {
        if (code != 37221) return false
        MusicNoticeStore.schedule(context)
        permissionResult?.success(MusicNoticeStore.permitted(context)); permissionResult = null
        return true
    }
}
