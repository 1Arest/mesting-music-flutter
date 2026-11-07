package com.mesting.music

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build

/** Own-process system history for opt-in diagnostics and narrow driver recovery.
 * Native traces pass through a bounded allowlist reader; descriptions, abort
 * messages, command lines and arbitrary trace contents are never exported.
 * A historical exit cannot be assigned to the currently installed build.
 */
object AppExitDiagnostics {
    fun recent(context: Context): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        return try {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            var remainingTraces = 2
            manager.getHistoricalProcessExitReasons(context.packageName, 0, 5)
                .filter { it.processName == context.packageName }
                .mapNotNull { exit ->
                    val reason = when (exit.reason) {
                        ApplicationExitInfo.REASON_CRASH -> "java_crash"
                        ApplicationExitInfo.REASON_CRASH_NATIVE -> "native_crash"
                        ApplicationExitInfo.REASON_ANR -> "anr"
                        ApplicationExitInfo.REASON_LOW_MEMORY -> "low_memory"
                        ApplicationExitInfo.REASON_SIGNALED -> "signal"
                        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "resource_limit"
                        else -> return@mapNotNull null
                    }
                    val row = mutableMapOf<String, Any>(
                        "reason" to reason,
                        "timestampMs" to exit.timestamp,
                        "status" to exit.status,
                        "pssKiB" to exit.pss,
                        "rssKiB" to exit.rss,
                    )
                    if (reason == "native_crash") {
                        row["nativeTrace"] = if (remainingTraces-- > 0) nativeTrace(exit)
                            else mapOf("status" to "not_requested")
                    }
                    row
                }
        } catch (_: RuntimeException) {
            // Vendor/OS diagnostic restrictions must never cause another crash.
            emptyList()
        }
    }

    private fun nativeTrace(exit: ApplicationExitInfo): Map<String, Any> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return mapOf("status" to "unsupported")
        return try {
            exit.traceInputStream?.use { NativeCrashTrace.read(it) }
                ?: mapOf("status" to "unavailable")
        } catch (_: Exception) {
            // A vendor restriction, overwritten trace or I/O failure is a
            // missing diagnostic, not an application or playback failure.
            mapOf("status" to "unavailable")
        }
    }
}
