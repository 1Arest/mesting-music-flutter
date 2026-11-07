package com.mesting.music

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Binder history queries and tombstone I/O must never run on the UI thread.
 * One worker/one queued call bounds work. Activity teardown drops old replies;
 * no Activity, trace stream or exception payload is retained by the worker.
 */
class AppExitDiagnosticsBridge(context: Context) {
    private val application = context.applicationContext
    private val closed = AtomicBoolean(false)
    private val replies = Handler(Looper.getMainLooper())
    private val worker = ThreadPoolExecutor(
        1, 1, 0L, TimeUnit.MILLISECONDS, ArrayBlockingQueue<Runnable>(1),
        { task -> Thread(task, "mesting-exit-diagnostics").apply { isDaemon = true } },
    )

    fun recent(result: MethodChannel.Result) {
        if (closed.get()) { result.success(emptyList<Any>()); return }
        try {
            worker.execute {
                val rows = AppExitDiagnostics.recent(application)
                if (!closed.get()) replies.post {
                    if (!closed.get()) result.success(rows)
                }
            }
        } catch (_: RuntimeException) {
            result.error("diagnostics_busy", "Exit diagnostics are unavailable", null)
        }
    }

    fun dispose() {
        closed.set(true)
        worker.shutdownNow()
        replies.removeCallbacksAndMessages(null)
    }
}
