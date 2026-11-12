package com.mesting.music

import android.content.Context
import android.os.Build
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Retains Impeller and shader-backed glass while avoiding a Vulkan driver
 * that has demonstrably crashed this process. No account data, raw trace or
 * device identifier is exported. OS updates invalidate the private decision.
 */
object RendererCompatibility {
    private const val PREFS = "renderer_compatibility_v123"
    @Volatile var selectedBackend = "auto"
        private set

    fun resolve(context: Context): String {
        if (context.packageName == "com.mesting.music.beta.benchmark") {
            // Compile-time sandbox override never applies to a daily build.
            return context.getString(R.string.mesting_benchmark_backend)
                .takeIf { it == "opengles" || it == "vulkan" } ?: "auto"
        }
        // The beta flavor supplies the patched engine even though public
        // releases now install as com.mesting.music. Do not lose recovery
        // merely because the user chose the public package identity.
        if (BuildConfig.FLAVOR != "beta" || Build.VERSION.SDK_INT < 31) return "auto"
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val savedOs = prefs.getString("os", null)
        val sameOs = savedOs == Build.FINGERPRINT
        if (sameOs && prefs.getBoolean("adrenoCrash", false)) return "opengles"
        // An OTA may replace the driver. A crash recorded before that change
        // must not immediately re-enable a recovery decision for the old OS.
        if (savedOs != null && !sameOs) {
            prefs.edit().putString("os", Build.FINGERPRINT).putBoolean("adrenoCrash", false)
                .putLong("ignoreBeforeMs", System.currentTimeMillis()).apply()
        }
        val ignoreBefore = prefs.getLong("ignoreBeforeMs", 0L)
        val executor = Executors.newSingleThreadExecutor { work ->
            Thread(work, "mesting-render-recovery").apply { isDaemon = true }
        }
        val check = executor.submit<Boolean> {
            val confirmed = AppExitDiagnostics.recent(context).any { exit ->
                (exit["timestampMs"] as? Long ?: 0L) >= ignoreBefore && VulkanCrashSignature.matches(exit)
            }
            if (confirmed) prefs.edit().putString("os", Build.FINGERPRINT)
                .putBoolean("adrenoCrash", true).apply()
            confirmed
        }
        // Diagnostic parsing is bounded in NativeCrashTrace. Do not hold up
        // a cold start indefinitely: a late positive takes effect next start.
        val confirmed = try { check.get(250, TimeUnit.MILLISECONDS) } catch (_: Exception) { false }
        executor.shutdown()
        return if (confirmed) "opengles" else "auto"
    }

    fun record(backend: String) {
        selectedBackend = backend
        // This is the embedder's request; the engine's own startup log is the
        // authority for the backend that actually initialized on the device.
        Log.i("MestingRenderer", "Impeller requestedBackend=$backend")
    }
}
