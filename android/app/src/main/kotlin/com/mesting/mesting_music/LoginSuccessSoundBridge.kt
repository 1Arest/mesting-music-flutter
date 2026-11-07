package com.mesting.music

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** UI-only one shot. SoundPool mixes into STREAM_MUSIC without taking focus
 * from the existing music service. It owns no queue, playback session or token. */
class LoginSuccessSoundBridge(context: Context, messenger: BinaryMessenger) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val pool = SoundPool.Builder().setMaxStreams(1).setAudioAttributes(
        AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
    ).build()
    private val channel = MethodChannel(messenger, "com.mesting.music/ui_sound")
    private var ready = false
    private var pending = false
    private var disposed = false
    private val sample: Int

    init {
        pool.setOnLoadCompleteListener { _, _, status ->
            ready = status == 0
            if (ready && pending && !disposed) { pending = false; play() }
        }
        sample = pool.load(context, R.raw.mesting_login_success, 1)
        channel.setMethodCallHandler { call, result ->
            if (call.method != "loginSuccess") result.notImplemented()
            else { if (ready) play() else pending = true; result.success(null) }
        }
    }
    private fun play() {
        if (!disposed && audio.ringerMode == AudioManager.RINGER_MODE_NORMAL &&
            audio.getStreamVolume(AudioManager.STREAM_MUSIC) > 0) {
            pool.play(sample, .65f, .65f, 1, 0, 1f)
        }
    }
    fun dispose() {
        disposed = true; pending = false
        channel.setMethodCallHandler(null)
        pool.release()
    }
}
