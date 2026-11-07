package com.mesting.music

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.security.MessageDigest
import java.util.ArrayDeque
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Device-only audio catalog. MediaStore scans, document traversal, metadata and
 * atomic index writes run on one worker; Flutter never blocks the main thread
 * on a directory or needs a broad filesystem path. No media is uploaded.
 *
 * MainActivity forwards activity/permission results to the two public hooks.
 */
class LocalMusicBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "com.mesting.music/local_music")
    private val worker = Executors.newSingleThreadExecutor()
    private val indexFile = AtomicFile(File(activity.filesDir, "local_music_library_v1.json"))
    private val artworkDirectory = File(activity.filesDir, "local_music_artwork")
    private val importedDirectory = File(activity.filesDir, "local_music_imports")
    private val results = mutableSetOf<Reply>() // Only touched on the UI thread.
    private var pendingPicker: Pair<Int, Reply>? = null
    private var pendingPermission: Reply? = null
    private var mutating = false
    private var disposed = false
    // Worker-confined cache avoids reparsing a large catalog for each lazy cover.
    private var cachedIndex: Index? = null
    // No embedded cover is a valid result. Remember it until an explicit
    // rescan/import, instead of opening MediaMetadataRetriever on each scroll.
    private val missingArtwork = mutableSetOf<String>()

    init { channel.setMethodCallHandler(this) }

    /** Explicit completed downloads enter the same device-only index. Queue
     * this before replying to Flutter so a subsequent load sees the new row. */
    fun indexDownloaded(uri: Uri) {
        worker.execute {
            try {
                val index = edit()
                val name = documentName(uri).orEmpty()
                val mime = activity.contentResolver.getType(uri).orEmpty()
                val row = readDocument(uri, idFor(uri.toString()), "downloads", "下载的音乐", "", "file", uri.toString(), name, mime)
                if (row != null) { index.entries[row["id"] as String] = row; store(index) }
            } catch (_: Exception) { /* The exported audio remains available for a later scan. */ }
        }
    }

    private class Failure(val code: String, override val message: String) : IOException(message)
    private data class Root(val uri: String, val name: String)
    private data class Index(
        val entries: LinkedHashMap<String, MutableMap<String, Any?>> = linkedMapOf(),
        val roots: MutableList<Root> = mutableListOf(),
        var notice: String = "",
    )

    private inner class Reply(private val result: MethodChannel.Result, private val mutation: Boolean) {
        private val done = AtomicBoolean()
        fun success(value: Any?) = finish { result.success(value) }
        fun error(code: String, message: String) = finish { result.error(code, message, null) }
        private fun finish(action: () -> Unit) {
            activity.runOnUiThread {
                if (done.compareAndSet(false, true)) {
                    results.remove(this)
                    if (mutation) mutating = false
                    action()
                }
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) { result.error("disposed", "本地音乐页面已关闭，请重新打开", null); return }
        val mutation = call.method in setOf("scan", "importFiles", "importDirectory", "refresh", "remove")
        if (mutation && mutating) {
            result.error("busy", "另一个本地音乐操作正在进行，请稍候", null); return
        }
        if (mutation) mutating = true
        val reply = Reply(result, mutation).also { results.add(it) }
        when (call.method) {
            "load" -> execute(reply) { snapshot(load()) }
            "scan" -> {
                if (hasAudioPermission()) execute(reply) { scanDevice() }
                else {
                    pendingPermission = reply
                    activity.requestPermissions(arrayOf(audioPermission()), PERMISSION_REQUEST)
                }
            }
            "importFiles" -> launchPicker(FILE_REQUEST, reply, Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "audio/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            })
            "importDirectory" -> launchPicker(DIRECTORY_REQUEST, reply, Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            })
            "refresh" -> execute(reply) { refresh() }
            "remove" -> execute(reply) {
                val index = edit()
                index.entries.remove(call.argument<String>("id") ?: "")
                // Removing an index row never deletes the user's original audio.
                store(index)
                snapshot(index)
            }
            "prepare" -> execute(reply) {
                val index = edit()
                val entry = index.entries[call.argument<String>("id")]
                    ?: throw Failure("unavailable", "这个文件已从本地音乐中移除")
                try {
                    activity.contentResolver.openAssetFileDescriptor(Uri.parse(entry["uri"] as String), "r")?.use { }
                        ?: throw FileNotFoundException()
                    entry["available"] = true
                    entry["artwork"] = artwork(entry)
                    store(index)
                    entry
                } catch (error: Exception) {
                    entry["available"] = false
                    store(index)
                    throw Failure("unavailable", "文件已移动、删除或授权已失效，请重新导入")
                }
            }
            "artwork" -> execute(reply) {
                val entry = load().entries[call.argument<String>("id")]
                if (entry == null) "" else artwork(entry)
            }
            "openSettings" -> {
                try {
                    activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")))
                    reply.success(null)
                } catch (_: Exception) { reply.error("settings_unavailable", "暂时无法打开系统设置，请手动授予音乐权限") }
            }
            else -> { results.remove(reply); if (mutation) mutating = false; result.notImplemented() }
        }
    }

    private fun execute(reply: Reply, action: () -> Any?) {
        if (disposed) { reply.error("disposed", "本地音乐页面已关闭"); return }
        worker.execute {
            try { reply.success(action()) }
            catch (error: Failure) { reply.error(error.code, error.message) }
            catch (_: SecurityException) { reply.error("permission_denied", "音乐访问权限已失效，请重新授权或选择文件") }
            catch (_: FileNotFoundException) { reply.error("unavailable", "文件或文件夹已移动、删除，请重新选择") }
            catch (_: Exception) { reply.error("local_music_failed", "本地音乐暂时无法读取，请重试或重新导入") }
        }
    }

    private fun launchPicker(requestCode: Int, reply: Reply, intent: Intent) {
        try {
            pendingPicker = requestCode to reply
            activity.startActivityForResult(intent, requestCode)
        } catch (_: Exception) {
            pendingPicker = null
            reply.error("picker_unavailable", "系统文件选择器无法打开，请稍后重试")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val pending = pendingPicker ?: return false
        if (pending.first != requestCode) return false
        pendingPicker = null
        val reply = pending.second
        if (resultCode != Activity.RESULT_OK || data == null) {
            execute(reply) { snapshot(load()) }; return true
        }
        val uris = linkedSetOf<Uri>()
        data.data?.let(uris::add)
        data.clipData?.let { clip ->
            for (position in 0 until minOf(clip.itemCount, MAX_FILE_PICK)) uris.add(clip.getItemAt(position).uri)
        }
        execute(reply) {
            val index = edit()
            var skipped = 0
            if (requestCode == DIRECTORY_REQUEST) {
                val uri = uris.firstOrNull() ?: throw Failure("empty_selection", "请选择一个音乐文件夹")
                if (!persistReadGrant(uri, data.flags)) {
                    throw Failure("permission_denied", "这个文件夹不支持持久访问，请改用选择音频文件")
                }
                val root = Root(uri.toString(), documentName(DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))) ?: "音乐文件夹")
                index.roots.removeAll { it.uri == root.uri }
                index.roots.add(root)
                val imported = scanTree(root, index)
                index.entries.entries.removeAll { it.value["origin"] == "tree" && it.value["originUri"] == root.uri }
                merge(index, imported)
            } else {
                for (uri in uris) {
                    if (index.entries.size >= MAX_TRACKS && !index.entries.containsKey(idFor(uri.toString()))) { skipped++; continue }
                    try {
                        val name = documentName(uri).orEmpty()
                        val mime = activity.contentResolver.getType(uri).orEmpty()
                        if (!isAudio(name, mime)) { skipped++; continue }
                        val stable = if (persistReadGrant(uri, data.flags)) uri else copySelectedFile(uri)
                        val row = readDocument(stable, idFor(uri.toString()), "imports:files", "导入的文件", "", "file", uri.toString(), name, mime)
                        if (row != null) {
                            val id = row["id"] as String
                            missingArtwork.remove(id)
                            index.entries[id] = row
                        } else skipped++
                    } catch (_: Exception) { skipped++ }
                }
                if (skipped > 0) index.notice = "$skipped 个文件无法导入或超出索引上限；其余文件已保留"
            }
            store(index)
            snapshot(index)
        }
        return true
    }

    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val reply = pendingPermission ?: return true
        pendingPermission = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            execute(reply) { scanDevice() }
        } else {
            val permanent = !activity.shouldShowRequestPermissionRationale(audioPermission())
            reply.error(if (permanent) "permission_permanently_denied" else "permission_denied", "扫描需要音乐和音频权限；也可以直接选择文件或文件夹导入")
        }
        return true
    }

    private fun audioPermission() = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE
    private fun hasAudioPermission() = activity.checkSelfPermission(audioPermission()) == PackageManager.PERMISSION_GRANTED

    private fun scanDevice(): Map<String, Any?> {
        if (!hasAudioPermission()) throw Failure("permission_denied", "请先授予音乐和音频权限")
        val index = edit()
        val fresh = mediaStoreEntries()
        fresh.keys.forEach(missingArtwork::remove)
        index.entries.entries.removeAll { it.value["origin"] == "device" }
        merge(index, fresh)
        if (fresh.size >= MAX_TRACKS) index.notice = "已读取前 $MAX_TRACKS 首音频；可选择具体文件夹继续管理"
        store(index)
        return snapshot(index)
    }

    private fun refresh(): Map<String, Any?> {
        val index = edit()
        if (hasAudioPermission()) {
            val fresh = mediaStoreEntries()
            index.entries.entries.removeAll { it.value["origin"] == "device" }
            merge(index, fresh)
            fresh.keys.forEach(missingArtwork::remove)
        } else {
            // Keep the recoverable catalog after a system-settings revocation,
            // but do not present these inaccessible MediaStore URIs as playable.
            index.entries.values.filter { it["origin"] == "device" }.forEach { it["available"] = false }
            if (index.entries.values.any { it["origin"] == "device" }) {
                index.notice = "音乐和音频权限已关闭；重新授权扫描，或选择文件导入"
            }
        }
        for (root in index.roots) {
            try {
                val fresh = scanTree(root, index)
                index.entries.entries.removeAll { it.value["origin"] == "tree" && it.value["originUri"] == root.uri }
                merge(index, fresh)
            } catch (_: Exception) {
                index.entries.values.filter { it["originUri"] == root.uri }.forEach { it["available"] = false }
                index.notice = "部分文件夹已不可访问，请重新选择文件夹以恢复授权"
            }
        }
        for (row in index.entries.values.filter { it["origin"] == "file" }) {
            row["available"] = try {
                activity.contentResolver.openAssetFileDescriptor(Uri.parse(row["uri"] as String), "r")?.use { true } ?: false
            } catch (_: Exception) { false }
        }
        store(index)
        return snapshot(index)
    }

    private fun mediaStoreEntries(): LinkedHashMap<String, MutableMap<String, Any?>> {
        val rows = linkedMapOf<String, MutableMap<String, Any?>>()
        val pathColumn = if (Build.VERSION.SDK_INT >= 29) MediaStore.Audio.Media.RELATIVE_PATH else MediaStore.Audio.Media.DATA
        val columns = arrayOf(MediaStore.Audio.Media._ID, MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST, MediaStore.Audio.Media.ALBUM, MediaStore.Audio.Media.DURATION, MediaStore.Audio.Media.DISPLAY_NAME, pathColumn)
        activity.contentResolver.query(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, columns, null, null, "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC")?.use { cursor ->
            while (cursor.moveToNext() && rows.size < MAX_TRACKS) {
                if (Thread.currentThread().isInterrupted) throw IOException()
                val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, cursor.long(MediaStore.Audio.Media._ID))
                val rawPath = cursor.text(pathColumn)
                val folderPath = if (Build.VERSION.SDK_INT >= 29) rawPath.trimEnd('/') else rawPath.substringBeforeLast('/', "")
                val folderName = folderPath.substringAfterLast('/').ifBlank { "其他音频" }
                val id = idFor(uri.toString())
                rows[id] = entry(id, uri, cursor.text(MediaStore.Audio.Media.TITLE).ifBlank { cursor.text(MediaStore.Audio.Media.DISPLAY_NAME) }, cursor.text(MediaStore.Audio.Media.ARTIST), cursor.text(MediaStore.Audio.Media.ALBUM), cursor.long(MediaStore.Audio.Media.DURATION), "media:$folderPath", folderName, folderPath, "device", uri.toString())
            }
        } ?: throw IOException("MediaStore query unavailable")
        return rows
    }

    /** SAF trees are explicitly selected by the user; traversal is bounded by
     * file count, directory count and depth, and never follows outside a tree. */
    private fun scanTree(root: Root, existing: Index): LinkedHashMap<String, MutableMap<String, Any?>> {
        val tree = Uri.parse(root.uri)
        data class Directory(val documentId: String, val path: String, val depth: Int)
        val pending = ArrayDeque<Directory>()
        pending.add(Directory(DocumentsContract.getTreeDocumentId(tree), root.name, 0))
        val seen = mutableSetOf<String>()
        val rows = linkedMapOf<String, MutableMap<String, Any?>>()
        var examined = 0
        var truncated = false
        while (pending.isNotEmpty() && seen.size < MAX_DIRECTORIES && examined < MAX_DOCUMENTS && rows.size < MAX_TRACKS) {
            if (Thread.currentThread().isInterrupted) throw IOException()
            val directory = pending.removeFirst()
            if (!seen.add(directory.documentId)) continue
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, directory.documentId)
            val columns = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE)
            activity.contentResolver.query(children, columns, null, null, null)?.use { cursor ->
                while (cursor.moveToNext() && examined < MAX_DOCUMENTS && rows.size < MAX_TRACKS) {
                    examined++
                    val documentId = cursor.text(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                    val name = cursor.text(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                    val mime = cursor.text(DocumentsContract.Document.COLUMN_MIME_TYPE)
                    if (documentId.isBlank()) continue
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        if (directory.depth < MAX_DEPTH && pending.size + seen.size < MAX_DIRECTORIES) pending.add(Directory(documentId, "${directory.path}/$name", directory.depth + 1)) else truncated = true
                    } else if (isAudio(name, mime)) {
                        val uri = DocumentsContract.buildDocumentUriUsingTree(tree, documentId)
                        val row = try { readDocument(uri, idFor(uri.toString()), "tree:${root.uri}:${directory.documentId}", directory.path.substringAfterLast('/'), directory.path, "tree", root.uri, name, mime) } catch (_: Exception) { null }
                        if (row != null) rows[row["id"] as String] = row
                    }
                }
            } ?: throw FileNotFoundException()
        }
        if (truncated || pending.isNotEmpty() || examined >= MAX_DOCUMENTS || rows.size >= MAX_TRACKS) existing.notice = "文件夹内容较多，已达到扫描上限；可分别选择子文件夹"
        return rows
    }

    private fun readDocument(uri: Uri, id: String, folderId: String, folderName: String, folderPath: String, origin: String, originUri: String, suppliedName: String = "", mimeHint: String = ""): MutableMap<String, Any?>? {
        val name = suppliedName.ifBlank { documentName(uri) ?: uri.lastPathSegment.orEmpty() }
        if (!isAudio(name, mimeHint.ifBlank { activity.contentResolver.getType(uri).orEmpty() })) return null
        var title = name.substringBeforeLast('.').ifBlank { "未命名音频" }
        var artist = ""
        var album = ""
        var duration = 0L
        val metadata = MediaMetadataRetriever()
        try {
            metadata.setDataSource(activity, uri)
            title = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)?.takeIf { it.isNotBlank() } ?: title
            artist = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST).orEmpty()
            album = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM).orEmpty()
            duration = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        } catch (_: Exception) {
            // Missing tags do not make an otherwise supported audio file invalid.
            activity.contentResolver.openAssetFileDescriptor(uri, "r")?.use { } ?: return null
        } finally { metadata.release() }
        return entry(id, uri, title, artist, album, duration, folderId, folderName, folderPath, origin, originUri)
    }

    private fun entry(id: String, uri: Uri, title: String, artist: String, album: String, duration: Long, folderId: String, folderName: String, folderPath: String, origin: String, originUri: String): MutableMap<String, Any?> = linkedMapOf(
        "id" to id, "uri" to uri.toString(), "title" to title.ifBlank { "未命名音频" },
        "artist" to artist.takeUnless { it.isBlank() || it == "<unknown>" }.orEmpty(),
        "album" to album.takeUnless { it.isBlank() || it == "<unknown>" }.orEmpty(),
        "durationMs" to duration.coerceAtLeast(0L), "folderId" to folderId,
        "folderName" to folderName, "folderPath" to folderPath, "origin" to origin,
        "originUri" to originUri, "available" to true, "artwork" to cachedArtwork(id),
    )

    private fun documentName(uri: Uri): String? = activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor -> if (cursor.moveToFirst()) cursor.text(OpenableColumns.DISPLAY_NAME) else null }
    private fun persistReadGrant(uri: Uri, flags: Int): Boolean = try {
        if (flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION == 0) false
        else { activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION); true }
    } catch (_: Exception) { false }

    /** Providers without persistable grants get an explicit imported copy. A
     * hard byte limit prevents an unbounded remote-document download. */
    private fun copySelectedFile(uri: Uri): Uri {
        importedDirectory.mkdirs()
        val target = File(importedDirectory, idFor(uri.toString()) + ".audio")
        val atomic = AtomicFile(target)
        val source = activity.contentResolver.openInputStream(uri) ?: throw FileNotFoundException()
        source.use { input ->
            val stream = atomic.startWrite()
            try {
                val buffer = ByteArray(64 * 1024)
                var copied = 0L
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    copied += count
                    if (copied > MAX_IMPORT_BYTES) throw Failure("file_too_large", "所选文件过大，请使用支持持久授权的文件管理器")
                    stream.write(buffer, 0, count)
                }
                atomic.finishWrite(stream)
            } catch (error: Exception) {
                // Explicitly re-importing an updated non-persistable document
                // replaces its private copy atomically. Failed copies preserve
                // the previous usable audio; never return an older copy early.
                atomic.failWrite(stream)
                throw error
            }
        }
        return Uri.fromFile(target)
    }

    private fun cachedArtwork(id: String): String {
        val file = File(artworkDirectory, "$id.jpg")
        return if (file.isFile) Uri.fromFile(file).toString() else ""
    }

    private fun artwork(entry: Map<String, Any?>): String {
        val id = entry["id"] as String
        cachedArtwork(id).takeIf { it.isNotEmpty() }?.let { return it }
        if (id in missingArtwork) return ""
        val metadata = MediaMetadataRetriever()
        try {
            val uri = Uri.parse(entry["uri"] as String)
            metadata.setDataSource(activity, uri)
            val bytes = metadata.embeddedPicture ?: return "".also { missingArtwork.add(id) }
            if (bytes.size > MAX_ARTWORK_BYTES) return "".also { missingArtwork.add(id) }
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            var sample = 1
            while (bounds.outWidth / sample > 512 || bounds.outHeight / sample > 512) sample *= 2
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return "".also { missingArtwork.add(id) }
            artworkDirectory.mkdirs()
            val file = AtomicFile(File(artworkDirectory, "$id.jpg"))
            val output = file.startWrite()
            try { bitmap.compress(Bitmap.CompressFormat.JPEG, 86, output); file.finishWrite(output) }
            catch (error: Exception) { file.failWrite(output); throw error }
            finally { bitmap.recycle() }
            // Artwork is a reconstructible bounded cache, never the audio itself.
            artworkDirectory.listFiles()?.filter { it.extension == "jpg" }?.sortedByDescending { it.lastModified() }?.drop(MAX_ARTWORK_FILES)?.forEach { it.delete() }
            return cachedArtwork(id)
        } catch (_: Exception) { return "" }
        finally { metadata.release() }
    }

    private fun load(): Index {
        cachedIndex?.let { return it }
        if (!indexFile.baseFile.exists() && !File(indexFile.baseFile.path + ".bak").exists()) return Index().also { cachedIndex = it }
        val bytes = indexFile.readFully()
        if (bytes.size > MAX_INDEX_BYTES) throw Failure("index_invalid", "本地音乐索引过大，请重新导入音乐")
        try {
            val json = JSONObject(String(bytes, Charsets.UTF_8))
            val index = Index()
            val rows = json.optJSONArray("entries") ?: JSONArray()
            for (position in 0 until minOf(rows.length(), MAX_TRACKS)) {
                val row = rows.optJSONObject(position) ?: continue
                val map = linkedMapOf<String, Any?>()
                for (key in row.keys()) map[key] = row.opt(key).takeUnless { it == JSONObject.NULL }
                val id = map["id"] as? String ?: continue
                val uri = Uri.parse(map["uri"] as? String ?: "")
                if (id.startsWith("local_") && uri.scheme in setOf("content", "file")) index.entries[id] = map
            }
            val roots = json.optJSONArray("roots") ?: JSONArray()
            for (position in 0 until minOf(roots.length(), MAX_DIRECTORIES)) {
                val root = roots.optJSONObject(position) ?: continue
                val uri = root.optString("uri")
                if (Uri.parse(uri).scheme == "content") index.roots.add(Root(uri, root.optString("name", "音乐文件夹")))
            }
            cachedIndex = index
            return index
        } catch (_: Exception) {
            // Preserve a damaged index before a subsequent explicit scan/import
            // replaces it; the actual selected audio files are never touched.
            val digest = MessageDigest.getInstance("SHA-256").digest(bytes).take(8).joinToString("") { "%02x".format(it) }
            val backup = File(activity.filesDir, "local_music_index_recovery_$digest.json")
            if (!backup.exists()) backup.writeBytes(bytes)
            return Index(notice = "原音乐索引无法读取，已保留恢复副本；请重新扫描或导入").also { cachedIndex = it }
        }
    }

    private fun store(index: Index) {
        val rows = JSONArray()
        index.entries.values.take(MAX_TRACKS).forEach { rows.put(JSONObject(it)) }
        val roots = JSONArray()
        index.roots.forEach { roots.put(JSONObject(mapOf("uri" to it.uri, "name" to it.name))) }
        val bytes = JSONObject().put("version", 1).put("entries", rows).put("roots", roots).toString().toByteArray(Charsets.UTF_8)
        if (bytes.size > MAX_INDEX_BYTES) throw Failure("index_too_large", "音乐索引已达到上限，请移除部分索引后重试")
        val stream = indexFile.startWrite()
        try { stream.write(bytes); indexFile.finishWrite(stream) }
        catch (error: Exception) { indexFile.failWrite(stream); throw error }
        cachedIndex = index
    }

    private fun edit(): Index {
        val current = load()
        return Index(LinkedHashMap(current.entries.mapValues { LinkedHashMap(it.value) }), current.roots.toMutableList())
    }

    private fun merge(index: Index, incoming: Map<String, MutableMap<String, Any?>>) {
        for ((id, row) in incoming) {
            missingArtwork.remove(id)
            if (index.entries.containsKey(id) || index.entries.size < MAX_TRACKS) index.entries[id] = row
            else index.notice = "音乐索引已达到 $MAX_TRACKS 首上限，已有音乐已保留"
        }
    }

    private fun snapshot(index: Index): Map<String, Any?> = mapOf(
        "entries" to index.entries.values.toList(), "permissionGranted" to hasAudioPermission(), "notice" to index.notice,
    )
    private fun idFor(value: String): String = "local_" + MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    private fun isAudio(name: String, mime: String) = mime.startsWith("audio/") || name.substringAfterLast('.', "").lowercase() in AUDIO_EXTENSIONS
    private fun Cursor.text(column: String): String { val position = getColumnIndex(column); return if (position >= 0 && !isNull(position)) getString(position).orEmpty() else "" }
    private fun Cursor.long(column: String): Long { val position = getColumnIndex(column); return if (position >= 0 && !isNull(position)) getLong(position) else 0L }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        pendingPicker = null
        pendingPermission = null
        results.toList().forEach { it.error("disposed", "本地音乐操作已结束，请重新打开页面") }
        worker.shutdownNow()
    }

    companion object {
        private const val FILE_REQUEST = 7120
        private const val DIRECTORY_REQUEST = 7121
        private const val PERMISSION_REQUEST = 7122
        private const val MAX_TRACKS = 10000
        private const val MAX_FILE_PICK = 256
        private const val MAX_DIRECTORIES = 512
        private const val MAX_DOCUMENTS = 30000
        private const val MAX_DEPTH = 16
        private const val MAX_IMPORT_BYTES = 512L * 1024 * 1024
        private const val MAX_ARTWORK_BYTES = 8 * 1024 * 1024
        private const val MAX_ARTWORK_FILES = 256
        private const val MAX_INDEX_BYTES = 24 * 1024 * 1024
        private val AUDIO_EXTENSIONS = setOf("mp3", "flac", "m4a", "aac", "wav", "ogg", "opus", "wma", "ape", "aiff", "aif", "alac", "dsf", "dff", "amr", "mka")
    }
}
