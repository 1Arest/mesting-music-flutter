package com.mesting.music

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** Fixed-action trampoline used by static shortcuts and immutable notifications.
 * Always launches the currently enabled branding alias, preserving startup art. */
class MusicEntryActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        MusicNoticeStore.enqueue(this, intent)
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        finish()
    }
}
