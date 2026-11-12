package com.mesting.music

import android.app.Application
import io.flutter.FlutterInjector

/** AudioService can create/cache the Flutter engine before an Activity supplies
 * shell arguments. Apply driver recovery at the application boundary so every
 * launcher alias and the audio-service engine use the same native backend.
 */
class MestingApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val backend = RendererCompatibility.resolve(this)
        RendererCompatibility.record(backend)
        if (backend == "opengles" || backend == "vulkan") {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(this)
            loader.ensureInitializationComplete(this, arrayOf(
                "--enable-impeller=true", "--impeller-backend=$backend"
            ))
        }
    }
}
