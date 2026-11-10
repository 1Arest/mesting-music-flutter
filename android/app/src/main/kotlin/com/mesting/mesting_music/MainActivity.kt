package com.mesting.music

import android.Manifest
import android.app.Activity
import android.app.ActivityOptions
import android.app.PendingIntent
import android.content.ComponentName
import android.content.ContentValues
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.Surface
import android.view.SurfaceHolder
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterSurfaceView
import android.view.animation.DecelerateInterpolator
import android.widget.LinearLayout
import android.widget.ImageView
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import android.media.MediaScannerConnection
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import kotlin.math.abs
import kotlin.math.roundToInt

open class MainActivity : AudioServiceActivity() {
    private var togetherLocationBridge: TogetherLocationBridge? = null
    private var audioOutputBridge: AudioOutputBridge? = null
    private var mediaVolumeBridge: MediaVolumeBridge? = null
    private var loginSuccessSoundBridge: LoginSuccessSoundBridge? = null
    private var hapticFeedbackBridge: HapticFeedbackBridge? = null
    private var localMusicBridge: LocalMusicBridge? = null
    private var neteaseCloudFileBridge: NeteaseCloudFileBridge? = null
    private var musicDownloadBridge: OfflineAudioStorageBridge? = null
    private var appExitDiagnosticsBridge: AppExitDiagnosticsBridge? = null
    private var requestedSurfaceHz = 0f
    private val refreshSurfaceCallbacks = java.util.WeakHashMap<SurfaceHolder, SurfaceHolder.Callback>()
    private lateinit var lyricsChannel: MethodChannel
    private var secureScreenRequests = 0
    private var pendingImageSave: PendingImageSave? = null

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        togetherLocationBridge?.dispose()
        togetherLocationBridge = null
        appExitDiagnosticsBridge?.dispose()
        appExitDiagnosticsBridge = null
        audioOutputBridge?.dispose()
        audioOutputBridge = null
        localMusicBridge?.dispose()
        localMusicBridge = null
        neteaseCloudFileBridge?.dispose()
        neteaseCloudFileBridge = null
        musicDownloadBridge?.dispose()
        musicDownloadBridge = null
        refreshSurfaceCallbacks.forEach { (holder, callback) -> holder.removeCallback(callback) }
        refreshSurfaceCallbacks.clear()
        hapticFeedbackBridge?.dispose()
        hapticFeedbackBridge = null
        loginSuccessSoundBridge?.dispose()
        loginSuccessSoundBridge = null
        mediaVolumeBridge?.dispose()
        mediaVolumeBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        togetherLocationBridge?.foreground(true)
        requestHighRefreshRate()
    }

    override fun onPause() {
        togetherLocationBridge?.foreground(false)
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(QishuiContextPlugin::class.java)) {
            flutterEngine.plugins.add(QishuiContextPlugin())
        }
        if (!flutterEngine.plugins.has(QishuiWebAuthPlugin::class.java)) {
            flutterEngine.plugins.add(QishuiWebAuthPlugin())
        }
        if (!flutterEngine.plugins.has(QishuiOfficialAudioPlugin::class.java)) {
            flutterEngine.plugins.add(QishuiOfficialAudioPlugin())
        }
        if (!flutterEngine.plugins.has(MusicHttpPlugin::class.java)) {
            flutterEngine.plugins.add(MusicHttpPlugin())
        }
        // The cached audio engine outlives this Activity. Its Together bridge
        // must detach with that engine, never when the UI merely backgrounds.
        if (!flutterEngine.plugins.has(TogetherBackgroundPlugin::class.java)) {
            flutterEngine.plugins.add(TogetherBackgroundPlugin())
        }
        togetherLocationBridge?.dispose()
        togetherLocationBridge = TogetherLocationBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        localMusicBridge?.dispose()
        localMusicBridge = LocalMusicBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        neteaseCloudFileBridge?.dispose()
        neteaseCloudFileBridge = NeteaseCloudFileBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        musicDownloadBridge?.dispose()
        musicDownloadBridge = OfflineAudioStorageBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        if (!flutterEngine.plugins.has(MusicEqualizerPlugin::class.java)) {
            flutterEngine.plugins.add(MusicEqualizerPlugin())
        }
        hapticFeedbackBridge?.dispose()
        hapticFeedbackBridge = HapticFeedbackBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        loginSuccessSoundBridge?.dispose()
        loginSuccessSoundBridge = LoginSuccessSoundBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        mediaVolumeBridge?.dispose()
        mediaVolumeBridge = MediaVolumeBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        audioOutputBridge?.dispose()
        audioOutputBridge = AudioOutputBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        lyricsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LYRICS_CHANNEL,
        )
        LyricsOverlayController.attach(this) { action ->
            lyricsChannel.invokeMethod("overlayAction", action)
        }
        lyricsChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "canDrawOverlays" -> result.success(canDrawOverlays())
                "requestPermission" -> {
                    requestOverlayPermission()
                    result.success(null)
                }
                "requestPermissionFromNotification" -> result.success(
                    requestOverlayPermissionFromNotification(),
                )
                "show" -> result.success(
                    if (canDrawOverlays()) {
                        LyricsOverlayController.show(call)
                        true
                    } else {
                        false
                    },
                )
                "hide" -> {
                    LyricsOverlayController.hide()
                    result.success(null)
                }
                "update" -> {
                    LyricsOverlayController.update(call)
                    result.success(null)
                }
                "isVisible" -> result.success(LyricsOverlayController.isVisible)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SYSTEM_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getRenderContext" -> {
                    // This is the embedder's request, not proof of which GPU
                    // backend initialized. Keep that distinction in reports.
                    result.success(mapOf(
                        "requestedBackend" to RendererCompatibility.selectedBackend,
                        "flavor" to BuildConfig.FLAVOR,
                    ))
                }
                "getRecentAppExits" -> {
                    val bridge = appExitDiagnosticsBridge ?: AppExitDiagnosticsBridge(this).also {
                        appExitDiagnosticsBridge = it
                    }
                    bridge.recent(result)
                }
                "getListeningDeviceInfo" -> {
                    // Runtime screen/device fields for this app's own signed
                    // playback events. No identifier or credential is logged.
                    val size = android.graphics.Point()
                    @Suppress("DEPRECATION")
                    windowManager.defaultDisplay.getRealSize(size)
                    result.success(mapOf(
                        "model" to Build.MODEL,
                        "systemVersion" to Build.VERSION.RELEASE,
                        "screenWidth" to size.x,
                        "screenHeight" to size.y,
                    ))
                }
                "bringAppToFront" -> {
                    packageManager.getLaunchIntentForPackage(packageName)?.let { intent ->
                        intent.addFlags(
                            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                                Intent.FLAG_ACTIVITY_NEW_TASK,
                        )
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "enterSecureScreen" -> {
                    secureScreenRequests += 1
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                "exitSecureScreen" -> {
                    secureScreenRequests = (secureScreenRequests - 1).coerceAtLeast(0)
                    if (secureScreenRequests == 0) {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BRAND_STYLE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBrandStyle" -> result.success(currentBrandStyle())
                "queueBrandStyle" -> {
                    val style = call.argument<String>("style")
                    if (style == null || !queueBrandStyle(style)) {
                        result.error("invalid_brand_style", "未知的装扮品牌套装", null)
                    } else {
                        result.success(null)
                    }
                }
                "applyQueuedBrandStyle" -> {
                    Thread(
                        {
                            val applied = applyPendingBrandStyle()
                            runOnUiThread {
                                result.success(applied)
                            }
                        },
                        "brand-style-apply",
                    ).start()
                }
                "setLaunchThemeMode" -> {
                    val mode = call.argument<String>("mode")
                    val updateLauncher =
                        call.argument<Boolean>("updateLauncher") ?: true
                    if (mode == null || !setLaunchThemeMode(mode, updateLauncher)) {
                        result.error("invalid_launch_theme", "未知的启动页主题模式", null)
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareDiagnosticJson" -> DiagnosticReportShare.share(this, call, result)
                "shareQishuiDiagnosticJson" -> DiagnosticReportShare.shareQishui(this, call, result)
                "shareNeteaseAdDiagnosticJson" -> DiagnosticReportShare.shareNeteaseAd(this, call, result)
                "shareToWeChat" -> SongLinkShare.openWeChat(this, call, result)
                "shareText" -> {
                    val text = call.argument<String>("text")?.trim()
                    if (text.isNullOrEmpty()) {
                        result.error("invalid_text", "分享内容不能为空", null)
                    } else {
                        val title = call.argument<String>("title") ?: "分享"
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        }
                        startActivity(Intent.createChooser(intent, title))
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_LIBRARY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImage" -> handleSaveImage(call, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_UPDATE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppInfo" -> result.success(currentAppInfo())
                "canRequestPackageInstalls" -> result.success(canRequestPackageInstalls())
                "openInstallPermission" -> openInstallPermission(result)
                "installApk" -> installApk(call, result)
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun currentAppInfo(): Map<String, Any> {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(0),
            )
        } else {
            packageManager.getPackageInfo(packageName, 0)
        }
        return mapOf(
            "packageName" to packageName,
            "versionName" to (info.versionName ?: ""),
            "versionCode" to packageVersionCode(info),
        )
    }

    private fun canRequestPackageInstalls(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
    }

    private fun openInstallPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(null)
            return
        }
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        )
        runCatching { startActivity(intent) }
            .onSuccess { result.success(null) }
            .onFailure {
                result.error("permission_settings_unavailable", "无法打开安装权限设置", null)
            }
    }

    private fun installApk(call: MethodCall, result: MethodChannel.Result) {
        val requestedPath = call.argument<String>("path")
        if (requestedPath.isNullOrBlank()) {
            result.error("invalid_path", "安装包路径无效", null)
            return
        }
        val file = runCatching { File(requestedPath).canonicalFile }.getOrNull()
        val allowedRoots = listOf(cacheDir, filesDir).mapNotNull { root ->
            runCatching { File(root, "app_updates").canonicalFile }.getOrNull()
        }
        val inAllowedRoot = file != null && allowedRoots.any { root ->
            file.path.startsWith("${root.path}${File.separator}")
        }
        if (
            file == null ||
            !inAllowedRoot ||
            !file.isFile ||
            file.extension.lowercase() != "apk" ||
            file.length() <= 0 ||
            file.length() > MAX_UPDATE_APK_BYTES
        ) {
            result.error("invalid_path", "安装包路径不安全", null)
            return
        }

        val archiveInfo = archivePackageInfo(file)
        if (archiveInfo == null) {
            result.error("invalid_apk", "安装包无效", null)
            return
        }
        if (archiveInfo.packageName != packageName) {
            result.error("apk_package_mismatch", "安装包与当前应用不匹配", null)
            return
        }
        val installedInfo = installedPackageInfoWithSignatures()
        if (packageVersionCode(archiveInfo) <= packageVersionCode(installedInfo)) {
            result.error("apk_version_not_newer", "安装包版本不高于当前版本", null)
            return
        }
        if (signingDigests(archiveInfo) != signingDigests(installedInfo)) {
            result.error("apk_signature_mismatch", "安装包签名校验失败", null)
            return
        }
        if (!canRequestPackageInstalls()) {
            result.error("install_permission_required", "尚未允许安装此来源的应用", null)
            return
        }

        val uri = runCatching {
            FileProvider.getUriForFile(
                this,
                "$packageName.update_files",
                file,
            )
        }.getOrElse {
            result.error("invalid_path", "无法安全共享安装包", null)
            return
        }
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = uri
            clipData = ClipData.newRawUri("Mesting 音乐更新", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        runCatching { startActivity(intent) }
            .onSuccess { result.success(null) }
            .onFailure {
                result.error("installer_unavailable", "系统安装程序不可用", null)
            }
    }

    @Suppress("DEPRECATION")
    private fun archivePackageInfo(file: File) = packageManager.getPackageArchiveInfo(
        file.path,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        },
    )

    @Suppress("DEPRECATION")
    private fun installedPackageInfoWithSignatures() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(
                    PackageManager.GET_SIGNING_CERTIFICATES.toLong(),
                ),
            )
        } else {
            packageManager.getPackageInfo(
                packageName,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    PackageManager.GET_SIGNING_CERTIFICATES
                } else {
                    PackageManager.GET_SIGNATURES
                },
            )
        }

    @Suppress("DEPRECATION")
    private fun packageVersionCode(info: android.content.pm.PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }

    @Suppress("DEPRECATION")
    private fun signingDigests(info: android.content.pm.PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners ?: emptyArray()
        } else {
            info.signatures ?: emptyArray()
        }
        return signatures.map { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
        }.toSet()
    }

    private fun handleSaveImage(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val mimeType = call.argument<String>("mimeType")
        val fileName = call.argument<String>("fileName")
        val validMimeType = mimeType?.takeIf { it in SUPPORTED_IMAGE_MIME_TYPES }
        if (
            bytes == null ||
            bytes.isEmpty() ||
            bytes.size > MAX_SAVED_IMAGE_BYTES ||
            validMimeType == null ||
            fileName.isNullOrBlank()
        ) {
            result.error("invalid_image", "图片文件不可用", null)
            return
        }
        val request = PendingImageSave(
            bytes = bytes,
            mimeType = validMimeType,
            fileName = fileName.replace(Regex("[^A-Za-z0-9._-]"), "_"),
            result = result,
        )
        if (
            Build.VERSION.SDK_INT in Build.VERSION_CODES.M until Build.VERSION_CODES.Q &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingImageSave != null) {
                result.error("save_in_progress", "另一张图片正在保存", null)
                return
            }
            pendingImageSave = request
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                IMAGE_SAVE_PERMISSION_REQUEST_CODE,
            )
            return
        }
        finishImageSave(request)
    }

    private fun finishImageSave(request: PendingImageSave) {
        runCatching {
            saveImageToGallery(request.bytes, request.mimeType, request.fileName)
        }.onSuccess { uri ->
            request.result.success(uri.toString())
        }.onFailure {
            request.result.error("save_failed", "图片保存失败，请稍后重试", null)
        }
    }

    private fun saveImageToGallery(bytes: ByteArray, mimeType: String, fileName: String): Uri {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            @Suppress("DEPRECATION")
            val pictures = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            val directory = File(pictures, "Mesting Music").apply { mkdirs() }
            val output = uniqueFile(directory, fileName)
            FileOutputStream(output).use { stream -> stream.write(bytes) }
            MediaScannerConnection.scanFile(
                this,
                arrayOf(output.absolutePath),
                arrayOf(mimeType),
                null,
            )
            return Uri.fromFile(output)
        }

        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            put(
                MediaStore.Images.Media.RELATIVE_PATH,
                "${Environment.DIRECTORY_PICTURES}/Mesting Music",
            )
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = contentResolver.insert(collection, values)
            ?: error("Unable to create MediaStore item")
        try {
            contentResolver.openOutputStream(uri, "w")?.use { stream ->
                stream.write(bytes)
            } ?: error("Unable to open MediaStore item")
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return uri
        } catch (error: Throwable) {
            contentResolver.delete(uri, null, null)
            throw error
        }
    }

    private fun uniqueFile(directory: File, requestedName: String): File {
        var candidate = File(directory, requestedName)
        if (!candidate.exists()) return candidate
        val dot = requestedName.lastIndexOf('.')
        val base = if (dot > 0) requestedName.substring(0, dot) else requestedName
        val extension = if (dot > 0) requestedName.substring(dot) else ""
        var suffix = 2
        while (candidate.exists()) {
            candidate = File(directory, "${base}_$suffix$extension")
            suffix += 1
        }
        return candidate
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        localMusicBridge?.onActivityResult(requestCode, resultCode, data)
        neteaseCloudFileBridge?.onActivityResult(requestCode, resultCode, data)
        musicDownloadBridge?.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (togetherLocationBridge?.permissions(requestCode) == true) return
        if (localMusicBridge?.onRequestPermissionsResult(requestCode, permissions, grantResults) == true) return
        if (requestCode != IMAGE_SAVE_PERMISSION_REQUEST_CODE) return
        val request = pendingImageSave ?: return
        pendingImageSave = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            finishImageSave(request)
        } else {
            request.result.error("permission_denied", "需要存储权限才能保存图片", null)
        }
    }

    private fun brandStyleComponents(): Map<String, List<ComponentName>> = mapOf(
        "coral" to listOf(
            launcherAlias("CoralLauncher"),
            launcherAlias("CoralLightLauncher"),
            launcherAlias("CoralDarkLauncher"),
        ),
        "morning_mist" to listOf(
            launcherAlias("MorningMistLauncher"),
        ),
        "midnight_vinyl" to listOf(
            launcherAlias("MidnightVinylLauncher"),
        ),
    )

    private fun legacyBrandStyleComponents(): Map<String, List<ComponentName>> = mapOf(
        "coral" to listOf(
            ComponentName(this, MainActivity::class.java),
            ComponentName(this, CoralLightActivity::class.java),
            ComponentName(this, CoralDarkActivity::class.java),
        ),
        "morning_mist" to listOf(
            ComponentName(this, MorningMistActivity::class.java),
        ),
        "midnight_vinyl" to listOf(
            ComponentName(this, MidnightVinylActivity::class.java),
        ),
    )

    private fun launcherAlias(name: String): ComponentName =
        // Flavor suffixes change the installed package, while Android classes
        // and manifest aliases retain the namespace declared by this source.
        ComponentName(packageName, "${MainActivity::class.java.`package`!!.name}.$name")

    private fun currentBrandStyle(): String {
        val preferences = getSharedPreferences(
            BRAND_STYLE_PREFERENCES,
            Context.MODE_PRIVATE,
        )
        // A queued value is valid only inside the explicit selection call that
        // created it. Never carry it into a later cold start: applying an alias
        // after the launch screen has appeared makes some OEM launchers briefly
        // render both the old and new desktop icons.
        if (preferences.contains(PENDING_BRAND_STYLE)) {
            preferences.edit().remove(PENDING_BRAND_STYLE).commit()
        }
        return preferences.getString(APPLIED_BRAND_STYLE, null)
            ?.takeIf(brandStyleComponents()::containsKey)
            ?: legacyBrandStyle()
            ?: activeBrandStyle()
            ?: "coral"
    }

    private fun queueBrandStyle(style: String): Boolean {
        if (!brandStyleComponents().containsKey(style)) return false
        return getSharedPreferences(BRAND_STYLE_PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(PENDING_BRAND_STYLE, style)
            .commit()
    }

    private fun applyPendingBrandStyle(): Boolean {
        val preferences = getSharedPreferences(
            BRAND_STYLE_PREFERENCES,
            Context.MODE_PRIVATE,
        )
        val pendingStyle = preferences.getString(PENDING_BRAND_STYLE, null)
        val appliedStyle = preferences.getString(APPLIED_BRAND_STYLE, null)
        val style = pendingStyle
            ?: appliedStyle?.takeIf(brandStyleComponents()::containsKey)
            ?: legacyBrandStyle()
            ?: activeBrandStyle()
            ?: "coral"
        val selected = componentForBrandStyle(style) ?: run {
            preferences.edit().remove(PENDING_BRAND_STYLE).commit()
            return false
        }
        try {
            activateBrandComponent(selected)
        } catch (_: RuntimeException) {
            // Do not retry a launcher mutation from the next cold start.
            preferences.edit().remove(PENDING_BRAND_STYLE).commit()
            return false
        }
        val enabled = brandStyleComponents().values
            .flatten()
            .filter(::isComponentEnabled)
        if (enabled.size != 1 || enabled.single() != selected) {
            preferences.edit().remove(PENDING_BRAND_STYLE).commit()
            return false
        }
        return preferences.edit()
            .putString(APPLIED_BRAND_STYLE, style)
            .remove(PENDING_BRAND_STYLE)
            .commit()
    }

    private fun activeBrandStyle(): String? =
        brandStyleComponents().entries.firstOrNull { (_, components) ->
            components.any(::isComponentEnabled)
        }?.key

    private fun legacyBrandStyle(): String? =
        legacyBrandStyleComponents().entries.firstOrNull { (_, components) ->
            components.any { component ->
                packageManager.getComponentEnabledSetting(component) ==
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            }
        }?.key

    private fun isComponentEnabled(component: ComponentName): Boolean =
        when (packageManager.getComponentEnabledSetting(component)) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED,
            -> false
            else -> try {
                packageManager.getActivityInfo(component, 0).enabled
            } catch (_: PackageManager.NameNotFoundException) {
                false
            }
        }

    private fun setLaunchThemeMode(mode: String, updateLauncher: Boolean): Boolean {
        if (mode !in setOf("light", "dark", "system")) return false
        val preferences = getSharedPreferences(
            BRAND_STYLE_PREFERENCES,
            Context.MODE_PRIVATE,
        )
        if (preferences.getString(LAUNCH_THEME_MODE, "system") == mode) {
            return true
        }
        if (!preferences.edit()
            .putString(LAUNCH_THEME_MODE, mode)
            .commit()
        ) {
            return false
        }
        if (updateLauncher && activeBrandStyle() == "coral") {
            try {
                activateBrandComponent(coralComponent(mode))
            } catch (_: RuntimeException) {
                return false
            }
        }
        return true
    }

    private fun componentForBrandStyle(style: String): ComponentName? = when (style) {
        "coral" -> coralComponent(currentLaunchThemeMode())
        "morning_mist" -> launcherAlias("MorningMistLauncher")
        "midnight_vinyl" -> launcherAlias("MidnightVinylLauncher")
        else -> null
    }

    private fun currentLaunchThemeMode(): String =
        getSharedPreferences(BRAND_STYLE_PREFERENCES, Context.MODE_PRIVATE)
            .getString(LAUNCH_THEME_MODE, "system") ?: "system"

    private fun coralComponent(mode: String): ComponentName = when (mode) {
        "light" -> launcherAlias("CoralLightLauncher")
        "dark" -> launcherAlias("CoralDarkLauncher")
        else -> launcherAlias("CoralLauncher")
    }

    private fun activateBrandComponent(selected: ComponentName) {
        val components = brandStyleComponents().values.flatten()
        val enabled = components.filter(::isComponentEnabled)
        if (enabled.size == 1 && enabled.single() == selected) return
        val updateFlags = launcherComponentUpdateFlags()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.setComponentEnabledSettings(
                components.map { component ->
                    PackageManager.ComponentEnabledSetting(
                        component,
                        if (component == selected) {
                            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                        } else {
                            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                        },
                        updateFlags,
                    )
                },
            )
            return
        }

        val previous = enabled.firstOrNull()
        try {
            components
                .filter { it != selected && isComponentEnabled(it) }
                .forEach { component ->
                    packageManager.setComponentEnabledSetting(
                        component,
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        updateFlags,
                    )
                }
            if (!isComponentEnabled(selected)) {
                packageManager.setComponentEnabledSetting(
                    selected,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    updateFlags,
                )
            }
        } catch (error: RuntimeException) {
            if (previous != null && !isComponentEnabled(previous)) {
                packageManager.setComponentEnabledSetting(
                    previous,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    updateFlags,
                )
            }
            throw error
        }
    }

    private fun launcherComponentUpdateFlags(): Int {
        var flags = PackageManager.DONT_KILL_APP
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Brand application runs on a worker thread. Persist the atomic
            // component state before reporting success so an immediate
            // SwipeUpClean cannot leave the launcher observing stale aliases.
            flags = flags or PackageManager.SYNCHRONOUS
        }
        return flags
    }

    private fun canDrawOverlays(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || canDrawOverlays()) return
        startActivity(
            Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"),
            ),
        )
    }

    private fun requestOverlayPermissionFromNotification(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || canDrawOverlays()) return false
        val activityIntent = Intent(
            applicationContext,
            LyricsOverlayPermissionActivity::class.java,
        ).addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP,
        )
        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            OVERLAY_PERMISSION_REQUEST_CODE,
            activityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val options = ActivityOptions.makeBasic()
                @Suppress("DEPRECATION")
                val backgroundStartMode = if (Build.VERSION.SDK_INT >= 36) {
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOW_ALWAYS
                } else {
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                }
                options.setPendingIntentBackgroundActivityStartMode(backgroundStartMode)
                pendingIntent.send(
                    applicationContext,
                    0,
                    null,
                    null,
                    null,
                    null,
                    options.toBundle(),
                )
            } else {
                pendingIntent.send()
            }
        }.isSuccess
    }

    /**
     * Flutter follows the display vsync and can render at 90/120 Hz. Some Android
     * devices still default third-party windows to 60 Hz, so prefer the
     * highest same-resolution mode up to 120 Hz (or the next available mode)
     * and also send its refresh-rate hint to the scheduler.
     */
    @Suppress("DEPRECATION")
    private fun requestHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val display = windowManager.defaultDisplay
        val activeMode = display.mode
        val sameResolutionModes = display.supportedModes.filter {
            it.physicalWidth == activeMode.physicalWidth &&
                it.physicalHeight == activeMode.physicalHeight &&
                it.refreshRate.isFinite() &&
                it.refreshRate > 0f
        }
        if (sameResolutionModes.isEmpty()) return

        val preferredMode =
            sameResolutionModes
                .filter { it.refreshRate <= TARGET_HIGH_REFRESH_RATE + REFRESH_RATE_TOLERANCE }
                .maxByOrNull { it.refreshRate }
                ?.takeIf { it.refreshRate > 60f + REFRESH_RATE_TOLERANCE }
                ?: sameResolutionModes
                    .filter { it.refreshRate > TARGET_HIGH_REFRESH_RATE + REFRESH_RATE_TOLERANCE }
                    .minByOrNull { it.refreshRate }
                ?: sameResolutionModes.maxByOrNull { it.refreshRate }
                ?: return

        val attributes = window.attributes
        if (!(
            attributes.preferredDisplayModeId == preferredMode.modeId &&
            abs(attributes.preferredRefreshRate - preferredMode.refreshRate) <= REFRESH_RATE_TOLERANCE
        )) {
            attributes.preferredDisplayModeId = preferredMode.modeId
            attributes.preferredRefreshRate = preferredMode.refreshRate
            window.attributes = attributes
        }
        requestedSurfaceHz = preferredMode.refreshRate
        // Window mode and Surface frame-rate are separate Android hints. The
        // latter must also be restored after a Flutter surface is recreated.
        window.decorView.post { hintFlutterSurfaces(window.decorView) }
    }

    private fun hintFlutterSurfaces(view: View) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        if (view is FlutterSurfaceView) {
            val holder = view.holder
            if (!refreshSurfaceCallbacks.containsKey(holder)) {
                val callback = object : SurfaceHolder.Callback {
                    override fun surfaceCreated(surface: SurfaceHolder) = hintSurface(surface)
                    override fun surfaceChanged(surface: SurfaceHolder, format: Int, width: Int, height: Int) = hintSurface(surface)
                    override fun surfaceDestroyed(surface: SurfaceHolder) = Unit
                }
                refreshSurfaceCallbacks[holder] = callback
                holder.addCallback(callback)
            }
            hintSurface(holder)
        } else if (view is ViewGroup) {
            for (index in 0 until view.childCount) hintFlutterSurfaces(view.getChildAt(index))
        }
    }

    private fun hintSurface(holder: SurfaceHolder) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && holder.surface.isValid && requestedSurfaceHz > 0f) {
            runCatching { holder.surface.setFrameRate(requestedSurfaceHz, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT) }
        }
    }

    companion object {
        private const val LYRICS_CHANNEL = "com.mesting.music/lyrics_overlay"
        private const val SYSTEM_CHANNEL = "com.mesting.music/system_media"
        private const val BRAND_STYLE_CHANNEL = "com.mesting.music/brand_style"
        private const val BRAND_STYLE_PREFERENCES = "mesting_brand_style"
        private const val PENDING_BRAND_STYLE = "pending_brand_style"
        private const val APPLIED_BRAND_STYLE = "applied_brand_style"
        private const val LAUNCH_THEME_MODE = "launch_theme_mode"
        private const val SHARE_CHANNEL = "com.mesting.music/share"
        private const val MEDIA_LIBRARY_CHANNEL = "com.mesting.music/media_library"
        private const val APP_UPDATE_CHANNEL = "com.mesting.music/app_update"
        private const val IMAGE_SAVE_PERMISSION_REQUEST_CODE = 7103
        private const val OVERLAY_PERMISSION_REQUEST_CODE = 7105
        private const val MAX_SAVED_IMAGE_BYTES = 10 * 1024 * 1024
        private const val MAX_UPDATE_APK_BYTES = 350L * 1024L * 1024L
        private val SUPPORTED_IMAGE_MIME_TYPES = setOf("image/jpeg", "image/png", "image/webp")
        private const val TARGET_HIGH_REFRESH_RATE = 120f
        private const val REFRESH_RATE_TOLERANCE = 0.5f
    }
}

private data class PendingImageSave(
    val bytes: ByteArray,
    val mimeType: String,
    val fileName: String,
    val result: MethodChannel.Result,
)

class LyricsOverlayPermissionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (canDrawOverlays()) {
            dispatchResult(true)
            return
        }
        @Suppress("DEPRECATION")
        startActivityForResult(
            Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"),
            ),
            REQUEST_OVERLAY_PERMISSION,
        )
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_OVERLAY_PERMISSION) {
            dispatchResult(canDrawOverlays())
        }
    }

    private fun canDrawOverlays(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)

    private fun dispatchResult(granted: Boolean) {
        LyricsOverlayController.emitPermissionResult(granted)
        finish()
    }

    companion object {
        private const val REQUEST_OVERLAY_PERMISSION = 7201
    }
}

class MorningMistActivity : MainActivity()

class MidnightVinylActivity : MainActivity()

class CoralLightActivity : MainActivity()

class CoralDarkActivity : MainActivity()

class CoralBrandActivity : MainActivity()

class CoralLightBrandActivity : MainActivity()

class CoralDarkBrandActivity : MainActivity()

class MorningMistBrandActivity : MainActivity()

class MidnightVinylBrandActivity : MainActivity()

