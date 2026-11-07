package com.mesting.music

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.MediaStore
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Owns persistable SAF grants, not the local-music index. Existing MediaStore
 * downloads remain readable and are never relocated by a storage migration. */
class OfflineAudioStorageBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.mesting.music/audio_download")
    private val worker = Executors.newSingleThreadExecutor()
    private val preferences = activity.getSharedPreferences("audio_download_storage", 0)
    private val permissions = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    private var pending: Pair<MethodCall, MethodChannel.Result>? = null
    private var disposed = false
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "cacheDirectory" -> result.success(File(activity.cacheDir, "audio-downloads").apply { mkdirs() }.absolutePath)
                "directory" -> result.success(directory()?.toString())
                "chooseDirectory", "export" -> select(call, result)
                "publish" -> publish(call, result)
                "readable" -> work(result) {
                    try { activity.contentResolver.openFileDescriptor(uri(call), "r")?.use { true } ?: false }
                    catch (_: Exception) { false }
                }
                "openDirectory" -> openDirectory(call, result)
                else -> result.notImplemented()
            }
        }
    }
    private fun directory(): Uri? {
        val saved = preferences.getString("tree", null)?.let(Uri::parse) ?: return null
        return saved.takeIf { tree -> activity.contentResolver.persistedUriPermissions.any {
            it.uri == tree && it.isReadPermission && it.isWritePermission
        } }
    }
    private fun uri(call: MethodCall): Uri {
        val value = Uri.parse(call.argument<String>("uri") ?: "")
        require(value.scheme == "content")
        return value
    }
    private fun select(call: MethodCall, result: MethodChannel.Result) {
        if (pending != null) { result.error("busy", "请先完成当前文件选择", null); return }
        pending = call to result
        try {
            val intent = if (call.method == "chooseDirectory") Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            else Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                val source = uri(call)
                type = activity.contentResolver.getType(source) ?: "audio/*"
                var name = call.argument<String>("name") ?: "music"
                activity.contentResolver.query(source, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) name = it.getString(0) ?: name
                }
                putExtra(Intent.EXTRA_TITLE, name)
            }
            intent.addFlags(permissions or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            directory()?.let { intent.putExtra("android.provider.extra.INITIAL_URI", it) }
            activity.startActivityForResult(intent, REQUEST)
        } catch (_: Exception) {
            pending = null
            result.error("picker", "无法打开系统文件选择器", null)
        }
    }
    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        // Browsing cannot change the saved directory or consume export state.
        if (request == BROWSE_REQUEST) return true
        if (request != REQUEST) return false
        val pair = pending ?: return true
        pending = null
        val target = data?.data
        if (code != Activity.RESULT_OK || target == null) {
            if (pair.first.method == "chooseDirectory") pair.second.success(null)
            else pair.second.error("cancelled", "已取消导出", null)
            return true
        }
        if (pair.first.method == "chooseDirectory") {
            try {
                require(DocumentsContract.isTreeUri(target))
                activity.contentResolver.takePersistableUriPermission(target, (data?.flags ?: 0) and permissions)
                require(activity.contentResolver.persistedUriPermissions.any { it.uri == target && it.isReadPermission && it.isWritePermission })
                check(preferences.edit().putString("tree", target.toString()).commit())
                pair.second.success(target.toString())
            } catch (_: Exception) { pair.second.error("permission", "文件夹授权未保存，请选择可写入的文件夹", null) }
        } else work(pair.second) {
            val source = uri(pair.first)
            require(source != target)
            try {
                activity.contentResolver.openInputStream(source)?.use { input ->
                    activity.contentResolver.openOutputStream(target, "w")?.use { output -> input.copyTo(output) } ?: error("output")
                } ?: error("input")
                null
            } catch (e: Exception) {
                try { activity.contentResolver.delete(target, null, null) } catch (_: Exception) { }
                throw e
            }
        }
        return true
    }
    private fun publish(call: MethodCall, result: MethodChannel.Result) = work(result) {
        val cache = File(activity.cacheDir, "audio-downloads").canonicalFile
        val source = File(call.argument<String>("path") ?: "").canonicalFile
        require(source.parentFile == cache && source.isFile && source.length() > 0)
        val tree = directory() ?: error("directory")
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val name = (call.argument<String>("name") ?: "music.mp3").replace(Regex("[\\\\/:*?\"<>|]"), "_").take(180)
        val target = DocumentsContract.createDocument(activity.contentResolver, parent, call.argument<String>("mime") ?: "audio/mpeg", name) ?: error("create")
        try {
            val bytes = activity.contentResolver.openOutputStream(target, "w")?.use { output -> source.inputStream().use { it.copyTo(output) } } ?: error("output")
            check(bytes == source.length())
            target.toString()
        } catch (e: Exception) {
            try { DocumentsContract.deleteDocument(activity.contentResolver, target) } catch (_: Exception) { }
            throw e
        }
    }
    private fun openDirectory(call: MethodCall, result: MethodChannel.Result) {
        try {
            val item = call.argument<String>("uri")?.let(Uri::parse)
            val folder = folderFor(item) ?: run {
                result.error("permission", "保存位置暂不可用，请重新授权目录，或导出这首歌", null)
                return
            }
            val view = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(folder, DocumentsContract.Document.MIME_TYPE_DIR)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }
            try {
                activity.startActivity(view)
            } catch (error: Exception) {
                if (error !is android.content.ActivityNotFoundException && error !is SecurityException) throw error
                // Some ROMs omit directory ACTION_VIEW. Their system document
                // browser can still show this real folder offline. A selected
                // document is ignored, never saved as a new download location.
                activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "audio/*"
                    putExtra(DocumentsContract.EXTRA_INITIAL_URI, folder)
                }, BROWSE_REQUEST)
            }
            result.success(null)
        } catch (_: SecurityException) {
            result.error("permission", "保存目录授权已失效，请重新授权目录，或导出这首歌", null)
        } catch (_: Exception) { result.error("file_manager", "系统文件管理器无法打开该文件夹，可使用导出选择保存位置", null) }
    }

    /** Locate a song's original folder, not the latest selected destination.
     * SAF grants retain their provider; old MediaStore songs retain their real
     * volume and relative path. No file is moved and no network is accessed. */
    private fun folderFor(item: Uri?): Uri? {
        val source = item ?: directory() ?: return null
        if (DocumentsContract.isTreeUri(source)) {
            val root = DocumentsContract.buildTreeDocumentUri(source.authority, DocumentsContract.getTreeDocumentId(source))
            if (activity.contentResolver.persistedUriPermissions.none { it.uri == root && it.isReadPermission }) return null
            return DocumentsContract.buildDocumentUriUsingTree(root, DocumentsContract.getTreeDocumentId(root))
        }
        if (source.authority == "com.android.externalstorage.documents") {
            val id = DocumentsContract.getDocumentId(source)
            val parent = id.substringBeforeLast('/', "")
            if (parent.isNotEmpty()) return DocumentsContract.buildDocumentUri(source.authority, parent)
        }
        if (source.authority == "media" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            activity.contentResolver.query(source, arrayOf(MediaStore.MediaColumns.RELATIVE_PATH, MediaStore.MediaColumns.VOLUME_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val relative = cursor.getString(0)?.trim('/') ?: return null
                    val volume = cursor.getString(1) ?: return null
                    val storage = if (volume == "external" || volume == "external_primary") "primary" else volume
                    return DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", "$storage:$relative")
                }
            }
        }
        return null
    }
    private fun work(result: MethodChannel.Result, action: () -> Any?) {
        worker.execute {
            try {
                val value = action()
                activity.runOnUiThread { if (!disposed) result.success(value) }
            } catch (_: Exception) {
                activity.runOnUiThread { if (!disposed) result.error("storage", "文件不可用或授权已失效，请检查保存位置和可用空间", null) }
            }
        }
    }
    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        pending?.second?.error("closed", "文件操作已结束", null)
        pending = null
        worker.shutdown()
    }
    companion object {
        private const val REQUEST = 7132
        private const val BROWSE_REQUEST = 7133
    }
}
