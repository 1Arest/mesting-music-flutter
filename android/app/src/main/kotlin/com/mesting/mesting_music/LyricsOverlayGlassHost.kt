package com.mesting.music

import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.View
import android.view.Window
import android.view.WindowManager
import java.util.function.Consumer
import kotlin.math.roundToInt

/** Native glass for the desktop overlay. A real overlay WINDOW is necessary:
 * blurring a lyric View with RenderEffect would blur its text, not wallpaper.
 * Android 12+ supplies bounded background blur; older/disabled systems receive
 * a legible translucent tint without screen capture or private system APIs. */
internal class LyricsOverlayGlassHost(private val context: Context) {
    private val manager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val dialog = Dialog(context, R.style.MestingLyricsOverlay)
    private var settings = false
    private val blurListener = Consumer<Boolean> { appearance(settings) }
    private var listening = false

    fun show(content: View, params: WindowManager.LayoutParams) {
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
        dialog.setCancelable(false)
        dialog.setContentView(content)
        dialog.window?.apply {
            setType(params.type)
            attributes = params
            decorView.setPadding(0, 0, 0, 0)
        }
        dialog.show()
        update(params)
        if (Build.VERSION.SDK_INT >= 31) {
            manager.addCrossWindowBlurEnabledListener(context.mainExecutor, blurListener)
            listening = true
        }
        appearance(false)
    }

    fun update(params: WindowManager.LayoutParams) {
        dialog.window?.attributes = params
    }

    fun appearance(isSettings: Boolean) {
        settings = isSettings
        val blur = Build.VERSION.SDK_INT >= 31 && manager.isCrossWindowBlurEnabled
        val radius = dp(if (settings) 28 else 26).toFloat()
        val glass = GradientDrawable(GradientDrawable.Orientation.TL_BR,
            if (blur) intArrayOf(Color.parseColor("#A848535F"), Color.parseColor("#9C18212E"))
            else intArrayOf(Color.parseColor("#EB35404B"), Color.parseColor("#E61B2430"))).apply {
            cornerRadius = radius
            setStroke(dp(1), Color.parseColor("#40FFFFFF"))
        }
        dialog.window?.apply {
            setBackgroundDrawable(glass)
            if (Build.VERSION.SDK_INT >= 31) setBackgroundBlurRadius(if (blur) dp(40) else 0)
            decorView.elevation = dp(8).toFloat()
        }
    }

    fun dismiss() {
        if (Build.VERSION.SDK_INT >= 31 && listening) {
            manager.removeCrossWindowBlurEnabledListener(blurListener)
        }
        listening = false
        dialog.dismiss()
    }
    private fun dp(value: Int) = (value * context.resources.displayMetrics.density).roundToInt()
}
