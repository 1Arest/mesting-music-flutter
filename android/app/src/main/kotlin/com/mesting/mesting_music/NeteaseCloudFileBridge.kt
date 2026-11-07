package com.mesting.music

import android.app.Activity
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/** A separate, explicit cloud-upload picker. It neither scans nor mutates the
 * device library. Copying and metadata extraction run off the main thread;
 * only an app-cache path crosses the channel, never the whole audio buffer. */
class NeteaseCloudFileBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.mesting.music/netease_cloud_file")
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var disposed = false
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "pick") { result.notImplemented(); return@setMethodCallHandler }
            if (pending != null) { result.error("busy", "请先完成当前文件选择", null); return@setMethodCallHandler }
            pending = result
            try {
                activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "audio/*"
                    putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }, REQUEST)
            } catch (_: Exception) { pending = null; result.error("picker", "无法打开文件选择器", null) }
        }
    }
    fun onActivityResult(request: Int, code: Int, intent: Intent?): Boolean {
        if (request != REQUEST) return false
        val result = pending ?: return true
        val uri = intent?.data
        if (code != Activity.RESULT_OK || uri == null) { pending = null; result.success(null); return true }
        worker.execute {
            var copied: File? = null
            try {
                var name = "music.mp3"
                activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) name = it.getString(0) ?: name
                }
                val extension = name.substringAfterLast('.', "mp3").lowercase()
                if (extension !in setOf("mp3", "flac", "m4a", "aac", "wav", "ogg", "opus")) throw Exception("unsupported")
                val prepared = File.createTempFile("netease-cloud-", ".$extension", activity.cacheDir)
                copied = prepared
                val digest = MessageDigest.getInstance("MD5")
                var length = 0L
                activity.contentResolver.openInputStream(uri)?.use { input ->
                    prepared.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            length += count
                            if (length > 512L * 1024 * 1024) throw Exception("too_large")
                            digest.update(buffer, 0, count); output.write(buffer, 0, count)
                        }
                    }
                } ?: throw Exception("unavailable")
                if (length == 0L) throw Exception("empty")
                val metadata = mutableMapOf<String, Any?>("path" to prepared.absolutePath,
                    "name" to name, "length" to length, "md5" to digest.digest().joinToString("") { "%02x".format(it) })
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(prepared.absolutePath)
                    metadata["title"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE) ?: name.substringBeforeLast('.')
                    metadata["artist"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST) ?: "未知艺术家"
                    metadata["album"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM) ?: "未知专辑"
                    metadata["bitrate"] = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE) ?: "999000"
                } finally { retriever.release() }
                activity.runOnUiThread {
                    if (!disposed && pending === result) { pending = null; result.success(metadata) }
                    else prepared.delete()
                }
            } catch (_: Exception) {
                copied?.delete()
                activity.runOnUiThread {
                    if (!disposed && pending === result) { pending = null; result.error("file", "文件无法读取、格式不支持或超过 512 MB，请重新选择", null) }
                }
            }
        }
        return true
    }
    fun dispose() {
        disposed = true; channel.setMethodCallHandler(null)
        pending?.error("closed", "文件选择已结束", null); pending = null
        worker.shutdown()
    }
    companion object { private const val REQUEST = 7130 }
}
