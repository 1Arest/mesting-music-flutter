package com.mesting.music

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Publishes completed cache files atomically to the user's music collection.
 * Android 10+ uses scoped MediaStore; older Android uses an explicit document
 * destination picker, avoiding a broad storage-permission request. */
class MusicDownloadBridge(private val activity: Activity, messenger: BinaryMessenger,
    private val index: (Uri) -> Unit) {
    private val channel = MethodChannel(messenger, "com.mesting.music/audio_download")
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: Pair<MethodCall, MethodChannel.Result>? = null
    private var disposed = false
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "cacheDirectory") {
                val directory = File(activity.cacheDir, "audio-downloads").apply { mkdirs() }
                result.success(directory.absolutePath)
            } else if (call.method == "publish") {
                if (pending != null) { result.error("busy", "请先完成保存位置选择", null); return@setMethodCallHandler }
                if (Build.VERSION.SDK_INT >= 29) publish(call, result, null)
                else {
                    pending = call to result
                    try {
                        activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = call.argument<String>("mime") ?: "audio/mpeg"
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }, REQUEST)
                    } catch (_: Exception) { pending = null; result.error("picker", "无法打开保存位置", null) }
                }
            } else result.notImplemented()
        }
    }
    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST) return false
        val pair = pending ?: return true
        pending = null
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) { pair.second.error("cancelled", "已取消保存", null); return true }
        try { activity.contentResolver.takePersistableUriPermission(uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION) } catch (_: Exception) { }
        publish(pair.first, pair.second, uri)
        return true
    }
    private fun publish(call: MethodCall, result: MethodChannel.Result, selected: Uri?) {
        worker.execute {
            var target: Uri? = selected
            try {
                val cache = File(activity.cacheDir, "audio-downloads").canonicalFile
                val source = File(call.argument<String>("path") ?: "").canonicalFile
                if (source.parentFile != cache || !source.isFile || source.length() == 0L) throw Exception("invalid")
                val name = (call.argument<String>("name") ?: "music.mp3").replace(Regex("[\\\\/:*?\"<>|]"), "_").take(180)
                if (target == null && Build.VERSION.SDK_INT >= 29) {
                    target = activity.contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        ContentValues().apply {
                            put(MediaStore.Audio.Media.DISPLAY_NAME, name)
                            put(MediaStore.Audio.Media.TITLE, call.argument<String>("title"))
                            put(MediaStore.Audio.Media.ARTIST, call.argument<String>("artist"))
                            put(MediaStore.Audio.Media.ALBUM, call.argument<String>("album"))
                            put(MediaStore.Audio.Media.MIME_TYPE, call.argument<String>("mime"))
                            put(MediaStore.Audio.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/Mesting Music")
                            put(MediaStore.Audio.Media.IS_PENDING, 1)
                        })
                }
                val uri = target ?: throw Exception("target")
                activity.contentResolver.openOutputStream(uri, "w")?.use { out -> source.inputStream().use { it.copyTo(out) } }
                    ?: throw Exception("output")
                if (Build.VERSION.SDK_INT >= 29 && selected == null) {
                    activity.contentResolver.update(uri, ContentValues().apply { put(MediaStore.Audio.Media.IS_PENDING, 0) }, null, null)
                }
                index(uri)
                activity.runOnUiThread { if (!disposed) result.success(uri.toString()) }
            } catch (_: Exception) {
                target?.let { try { activity.contentResolver.delete(it, null, null) } catch (_: Exception) { } }
                activity.runOnUiThread { if (!disposed) result.error("save", "歌曲保存未完成，请检查可用空间后重试", null) }
            }
        }
    }
    fun dispose() {
        disposed = true; channel.setMethodCallHandler(null)
        pending?.second?.error("closed", "保存已结束", null); pending = null; worker.shutdown()
    }
    companion object { private const val REQUEST = 7131 }
}
