package com.mesting.music

import android.app.job.JobParameters
import android.app.job.JobService
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/** A bounded system job survives removal from recents without a permanent
 * service or a second audio player. Android controls its actual execution time. */
class MusicNoticeJobService : JobService() {
    private val handler = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var running: JobParameters? = null
    private val deadline = Runnable { finish() }
    override fun onStartJob(params: JobParameters): Boolean {
        if (running != null) return false
        if (!MusicNoticeStore.permitted(this)) { MusicNoticeStore.schedule(this); return false }
        running = params
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            // Disable automatic registration: audio_service and UI plugins must
            // not create media clients or attach a second player in this engine.
            val worker = FlutterEngine(applicationContext, null, false)
            engine = worker
            worker.plugins.add(com.it_nomads.fluttersecurestorage.FlutterSecureStoragePlugin())
            worker.plugins.add(io.flutter.plugins.pathprovider.PathProviderPlugin())
            worker.plugins.add(io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin())
            worker.plugins.add(MusicHttpPlugin())
            worker.plugins.add(MusicNotificationPlugin { handler.post { finish() } })
            handler.postDelayed(deadline, 90_000L)
            worker.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "notificationBackgroundMain"))
            return true
        } catch (_: Exception) { finish(); return false }
    }
    private fun finish() {
        val params = running ?: return
        running = null; handler.removeCallbacks(deadline)
        engine?.destroy(); engine = null
        jobFinished(params, false)
    }
    override fun onStopJob(params: JobParameters): Boolean {
        running = null; handler.removeCallbacks(deadline)
        engine?.destroy(); engine = null
        return true
    }
}
