package com.mesting.music

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.LinearLayout
import android.widget.ImageView
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import io.flutter.plugin.common.MethodCall
import kotlin.math.abs
import kotlin.math.roundToInt

/** Owns lyric content, gestures and saved appearance. Window optics are kept in
 * LyricsOverlayGlassHost so settings, dragging and playback actions never own
 * the platform blur lifecycle or a second media service. */
internal object LyricsOverlayController {
    private const val COMPACT_OVERLAY_MAX_WIDTH_DP = 376
    private const val COMPACT_OVERLAY_SIDE_INSET_DP = 6
    private const val OVERLAY_DRAG_EDGE_INSET_DP = 6
    private const val SETTINGS_OVERLAY_MAX_WIDTH_DP = 360
    private const val SETTINGS_OVERLAY_SIDE_INSET_DP = 10

    private val colorPalette = intArrayOf(
        Color.WHITE,
        Color.rgb(255, 212, 92),
        Color.rgb(255, 127, 160),
        Color.rgb(112, 226, 255),
        Color.rgb(140, 255, 181),
        Color.rgb(201, 167, 255),
        Color.rgb(255, 157, 113),
        Color.rgb(126, 169, 255),
    )

    private var context: Context? = null
    private var windowManager: WindowManager? = null
    private var glassHost: LyricsOverlayGlassHost? = null
    private var root: LinearLayout? = null
    private var compactContent: LinearLayout? = null
    private var compactHeader: LinearLayout? = null
    private var compactLyricsSurface: LinearLayout? = null
    private var compactDivider: View? = null
    private var compactControls: LinearLayout? = null
    private var settingsContent: LinearLayout? = null
    private var lyricStatusLabel: TextView? = null
    private var currentLine: TextView? = null
    private var nextLine: TextView? = null
    private var playButton: TextView? = null
    private var lockButton: TextView? = null
    private var settingsButton: TextView? = null
    private var favoriteButton: TextView? = null
    private var lockStateLabel: TextView? = null
    private var settingsPreview: TextView? = null
    private var fontSizeValue: TextView? = null
    private var fontSizeSeek: SeekBar? = null
    private var lockSwitch: Switch? = null
    private val colorButtons = mutableListOf<Pair<Int, TextView>>()
    private var params: WindowManager.LayoutParams? = null
    private var actionSink: ((Map<String, Any>) -> Unit)? = null
    private var locked = false
    private var fontSize = 17f
    private var textColor = Color.WHITE
    private var controlsExpanded = false
    private var settingsExpanded = false
    private var syncingSettingsControls = false
    private var playing = false
    private var favorite = false
    private var displayedCurrentLine = ""
    private var displayedNextLine = ""
    private var lyricAnimationGeneration = 0L
    var isVisible: Boolean = false
        private set

    fun attach(activity: MainActivity, sink: (Map<String, Any>) -> Unit) {
        context = activity.applicationContext
        windowManager = activity.applicationContext
            .getSystemService(Context.WINDOW_SERVICE) as WindowManager
        actionSink = sink
    }

    fun emitPermissionResult(granted: Boolean) {
        actionSink?.invoke(
            mapOf(
                "action" to "notificationPermissionResult",
                "granted" to granted,
            ),
        )
    }

    fun show(call: MethodCall) {
        if (isVisible) {
            update(call)
            return
        }
        val appContext = context ?: return
        if (windowManager == null) return
        var dragStartWindowX = 0
        var dragStartWindowY = 0
        var dragStartTouchX = 0f
        var dragStartTouchY = 0f
        var dragging = false
        val layout = object : LinearLayout(appContext) {
            override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
                if (locked || settingsExpanded) return super.onInterceptTouchEvent(event)
                val layoutParams = params ?: return super.onInterceptTouchEvent(event)
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        dragStartWindowX = layoutParams.x
                        dragStartWindowY = layoutParams.y
                        dragStartTouchX = event.rawX
                        dragStartTouchY = event.rawY
                        dragging = false
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val distance = abs(event.rawX - dragStartTouchX) +
                            abs(event.rawY - dragStartTouchY)
                        if (distance >= dp(5)) {
                            dragging = true
                            return true
                        }
                    }
                }
                return false
            }

            override fun onTouchEvent(event: MotionEvent): Boolean {
                if (locked || settingsExpanded) return false
                val layoutParams = params ?: return false
                when (event.actionMasked) {
                    MotionEvent.ACTION_OUTSIDE -> {
                        if (controlsExpanded || settingsExpanded) {
                            if (settingsExpanded) setSettingsExpanded(false)
                            setControlsExpanded(false)
                        }
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        dragging = true
                        layoutParams.x = dragStartWindowX +
                            (event.rawX - dragStartTouchX).roundToInt()
                        layoutParams.y = dragStartWindowY +
                            (event.rawY - dragStartTouchY).roundToInt()
                        clampOverlayPosition(this, layoutParams)
                        glassHost?.update(layoutParams)
                    }
                    MotionEvent.ACTION_UP,
                    MotionEvent.ACTION_CANCEL -> {
                        if (!dragging && event.actionMasked == MotionEvent.ACTION_UP) {
                            performClick()
                        }
                        dragging = false
                    }
                }
                return true
            }

            override fun performClick(): Boolean = super.performClick()
        }.apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(6), dp(8), dp(6))
            setBackgroundColor(Color.TRANSPARENT)
            elevation = 0f
        }
        compactContent = buildCompactContent(appContext).also { content ->
            compactHeader = (content.getChildAt(0) as? LinearLayout)?.apply {
                visibility = View.GONE
            }
            compactDivider = content.getChildAt(2).apply {
                visibility = View.GONE
            }
            compactControls = (content.getChildAt(3) as? LinearLayout)?.apply {
                visibility = View.GONE
            }
            layout.addView(content)
        }
        settingsContent = buildSettingsContent(appContext).also {
            it.visibility = View.GONE
            layout.addView(it)
        }

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val screenWidth = appContext.resources.displayMetrics.widthPixels
        val compactWidth = overlayWidth(
            screenWidth,
            COMPACT_OVERLAY_MAX_WIDTH_DP,
            COMPACT_OVERLAY_SIDE_INSET_DP,
        )
        params = WindowManager.LayoutParams(
            compactWidth,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = ((screenWidth - compactWidth) / 2).coerceAtLeast(0)
            y = dp(110)
        }
        root = layout
        layout.setOnClickListener {
            if (!locked && !settingsExpanded) {
                setControlsExpanded(!controlsExpanded)
            }
        }
        glassHost = LyricsOverlayGlassHost(appContext).also { it.show(layout, params!!) }
        isVisible = true
        // Apply the same compact state on first show as after a later collapse:
        // one current line, no hidden header/control space and the same padding.
        setControlsExpanded(false)
        layout.post {
            params?.let { layoutParams ->
                clampOverlayPosition(layout, layoutParams)
                runCatching { glassHost?.update(layoutParams) }
            }
        }
        update(call)
    }

    fun update(call: MethodCall) {
        val args = call.arguments as? Map<*, *> ?: return
        updateLyricLines(
            current = args["current"] as? String ?: "Mesting 音乐",
            next = args["next"] as? String ?: "",
        )
        playing = args["playing"] as? Boolean ?: false
        favorite = args["favorite"] as? Boolean ?: favorite
        playButton?.setCompoundDrawablesRelativeWithIntrinsicBounds(
            if (playing) R.drawable.ic_overlay_pause else R.drawable.ic_overlay_play,
            0,
            0,
            0,
        )
        lyricStatusLabel?.text = if (playing) "正在播放" else "已暂停"
        val requestedLocked = args["locked"] as? Boolean ?: locked
        locked = requestedLocked
        fontSize = ((args["fontSize"] as? Number)?.toFloat() ?: fontSize).coerceIn(14f, 34f)
        val color = args["textColor"] as? String
        if (color != null) {
            runCatching { Color.parseColor(color) }.getOrNull()?.let { textColor = it }
        }
        if (locked) {
            if (settingsExpanded) setSettingsExpanded(false)
            setControlsExpanded(false)
        }
        applyAppearance()
    }

    private fun updateLyricLines(current: String, next: String) {
        val currentView = currentLine ?: return
        val nextView = nextLine ?: return
        if (displayedCurrentLine.isEmpty()) {
            displayedCurrentLine = current
            displayedNextLine = next
            currentView.text = current
            nextView.text = next
            currentView.alpha = 1f
            nextView.alpha = 1f
            currentView.translationY = 0f
            nextView.translationY = 0f
            return
        }
        if (current == displayedCurrentLine) {
            if (next != displayedNextLine) {
                displayedNextLine = next
                nextView.text = next
            }
            return
        }

        lyricAnimationGeneration += 1
        val generation = lyricAnimationGeneration
        val travel = dp(7).toFloat()
        currentView.animate().cancel()
        nextView.animate().cancel()
        nextView.animate()
            .alpha(0f)
            .translationY(-travel)
            .setDuration(LYRIC_EXIT_DURATION_MS)
            .start()
        currentView.animate()
            .alpha(0f)
            .translationY(-travel)
            .setDuration(LYRIC_EXIT_DURATION_MS)
            .withEndAction {
                if (generation != lyricAnimationGeneration) return@withEndAction
                displayedCurrentLine = current
                displayedNextLine = next
                currentView.text = current
                nextView.text = next
                settingsPreview?.text = current
                currentView.alpha = 0f
                nextView.alpha = 0f
                currentView.translationY = travel
                nextView.translationY = travel
                currentView.animate()
                    .alpha(1f)
                    .translationY(0f)
                    .setDuration(LYRIC_ENTER_DURATION_MS)
                    .setInterpolator(DecelerateInterpolator(1.35f))
                    .start()
                nextView.animate()
                    .alpha(1f)
                    .translationY(0f)
                    .setDuration(LYRIC_ENTER_DURATION_MS)
                    .setInterpolator(DecelerateInterpolator(1.35f))
                    .start()
            }
            .start()
    }

    fun hide() {
        if (root == null) return
        lyricAnimationGeneration += 1
        currentLine?.animate()?.cancel()
        nextLine?.animate()?.cancel()
        glassHost?.dismiss()
        glassHost = null
        root = null
        compactContent = null
        compactHeader = null
        compactLyricsSurface = null
        compactDivider = null
        compactControls = null
        settingsContent = null
        lyricStatusLabel = null
        currentLine = null
        nextLine = null
        playButton = null
        lockButton = null
        settingsButton = null
        favoriteButton = null
        lockStateLabel = null
        settingsPreview = null
        fontSizeValue = null
        fontSizeSeek = null
        lockSwitch = null
        colorButtons.clear()
        params = null
        controlsExpanded = false
        settingsExpanded = false
        displayedCurrentLine = ""
        displayedNextLine = ""
        isVisible = false
    }

    private fun buildCompactContent(appContext: Context) = LinearLayout(appContext).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL

        addView(
            LinearLayout(appContext).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(
                    ImageView(appContext).apply {
                        setImageResource(R.drawable.mesting_mark_foreground)
                        scaleType = ImageView.ScaleType.CENTER_INSIDE
                        setPadding(dp(6), dp(6), dp(6), dp(6))
                        contentDescription = "Mesting"
                        background = roundedBackground("#0EFFFFFF", "#2EFFFFFF", 10f)
                    },
                    LinearLayout.LayoutParams(dp(32), dp(32)).apply {
                        marginEnd = dp(10)
                    },
                )
                addView(
                    settingText(
                        appContext,
                        "Mesting Music",
                        12f,
                        Color.parseColor("#E8FFFFFF"),
                        true,
                    ).apply {
                        includeFontPadding = false
                        letterSpacing = .02f
                    },
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
                )
                lockButton = controlButton(appContext, "", "lock").also(::addView)
                addView(controlButton(appContext, "", "close"))
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        addView(
            LinearLayout(appContext).apply {
                compactLyricsSurface = this
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(4), dp(12), dp(4), dp(12))
                setBackgroundColor(Color.TRANSPARENT)
                currentLine = lyricTextView(appContext, fontSize, true).also {
                    it.setOnClickListener {
                        if (!locked) setControlsExpanded(!controlsExpanded)
                    }
                    addView(it)
                }
                nextLine = lyricTextView(appContext, fontSize - 4f, false).also {
                    it.setOnClickListener {
                        if (!locked) setControlsExpanded(!controlsExpanded)
                    }
                    addView(
                        it,
                        LinearLayout.LayoutParams(
                            LinearLayout.LayoutParams.MATCH_PARENT,
                            LinearLayout.LayoutParams.WRAP_CONTENT,
                        ).apply { topMargin = dp(7) },
                    )
                }
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(5) },
        )

        addView(
            View(appContext).apply {
                background = dividerBackground()
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(2),
            ).apply {
                marginStart = dp(48)
                marginEnd = dp(48)
            },
        )

        addView(
            LinearLayout(appContext).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(0), dp(8), dp(0), dp(2))
                settingsButton = controlButton(appContext, "", "settings").also(::addView)
                addView(View(appContext), LinearLayout.LayoutParams(0, dp(1), 1f))
                addView(controlButton(appContext, "", "previous"))
                playButton = controlButton(appContext, "", "playPause").also(::addView)
                addView(controlButton(appContext, "", "next"))
                addView(View(appContext), LinearLayout.LayoutParams(0, dp(1), 1f))
                favoriteButton = controlButton(appContext, "", "favorite").also(::addView)
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(2) },
        )
    }

    private fun buildSettingsContent(appContext: Context) = LinearLayout(appContext).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        addView(
            LinearLayout(appContext).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(
                    LinearLayout(appContext).apply {
                        orientation = LinearLayout.VERTICAL
                        addView(settingText(appContext, "桌面歌词", 18f, Color.WHITE, true))
                        addView(settingText(appContext, "样式修改会立即生效", 11f, Color.parseColor("#8CFFFFFF")))
                    },
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
                )
                addView(
                    settingButton(appContext, "完成") { setSettingsExpanded(false) },
                    LinearLayout.LayoutParams(dp(68), dp(38)),
                )
            },
        )

        settingsPreview = settingText(appContext, "让音乐停留在桌面", fontSize, textColor, true).also {
            it.gravity = Gravity.CENTER
            it.maxLines = 2
            it.background = gradientBackground(
                intArrayOf(
                    Color.parseColor("#20FFFFFF"),
                    Color.parseColor("#0CFFFFFF"),
                ),
                Color.parseColor("#28FFFFFF"),
                18f,
            )
            it.setPadding(dp(10), dp(12), dp(10), dp(12))
            addView(
                it,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(76),
                ).apply { topMargin = dp(15) },
            )
        }

        addView(
            LinearLayout(appContext).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(
                    settingText(appContext, "字体大小", 14f, Color.WHITE, true),
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
                )
                fontSizeValue = settingText(appContext, "${fontSize.roundToInt()}sp", 13f, Color.parseColor("#FF70B7FF"), true).also(::addView)
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(16) },
        )
        fontSizeSeek = SeekBar(appContext).also { seek ->
            seek.max = 20
            seek.progress = (fontSize - 14f).roundToInt()
            seek.progressTintList = ColorStateList.valueOf(Color.parseColor("#FF0A84FF"))
            seek.thumbTintList = ColorStateList.valueOf(Color.parseColor("#FF0A84FF"))
            seek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(view: SeekBar?, progress: Int, fromUser: Boolean) {
                    if (!fromUser) return
                    fontSize = (14 + progress).toFloat()
                    applyAppearance()
                    emitSettingsChanged()
                }
                override fun onStartTrackingTouch(view: SeekBar?) = Unit
                override fun onStopTrackingTouch(view: SeekBar?) = Unit
            })
            addView(seek, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(42)))
        }

        addView(
            settingText(appContext, "字体颜色", 14f, Color.WHITE, true),
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(10) },
        )
        addView(
            LinearLayout(appContext).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                clipChildren = false
                clipToPadding = false
                setPadding(dp(2), dp(5), dp(2), dp(2))
                colorPalette.toList().chunked(4).forEach { rowColors ->
                    addView(
                        LinearLayout(appContext).apply {
                            orientation = LinearLayout.HORIZONTAL
                            gravity = Gravity.CENTER
                            clipChildren = false
                            clipToPadding = false
                            rowColors.forEach { color ->
                                val button = TextView(appContext).apply {
                                    gravity = Gravity.CENTER
                                    includeFontPadding = false
                                    textSize = 15f
                                    setTextColor(
                                        if (color == Color.WHITE) {
                                            Color.DKGRAY
                                        } else {
                                            Color.WHITE
                                        },
                                    )
                                    contentDescription = "选择歌词颜色"
                                    setOnClickListener {
                                        textColor = color
                                        applyAppearance()
                                        emitSettingsChanged()
                                    }
                                }
                                colorButtons += color to button
                                addView(
                                    button,
                                    LinearLayout.LayoutParams(dp(44), dp(44)).apply {
                                        marginStart = dp(4)
                                        marginEnd = dp(4)
                                        topMargin = dp(3)
                                        bottomMargin = dp(3)
                                    },
                                )
                            }
                        },
                        LinearLayout.LayoutParams(
                            LinearLayout.LayoutParams.MATCH_PARENT,
                            LinearLayout.LayoutParams.WRAP_CONTENT,
                        ),
                    )
                }
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        addView(
            LinearLayout(appContext).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(12), dp(10), dp(8), dp(10))
                background = roundedBackground("#18FFFFFF", "#18FFFFFF", 16f)
                addView(
                    LinearLayout(appContext).apply {
                        orientation = LinearLayout.VERTICAL
                        addView(settingText(appContext, "锁定桌面歌词", 14f, Color.WHITE, true))
                        addView(settingText(appContext, "锁定后防止误拖动", 10f, Color.parseColor("#80FFFFFF")))
                    },
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
                )
                @Suppress("DEPRECATION")
                lockSwitch = Switch(appContext).also { toggle ->
                    toggle.isChecked = locked
                    toggle.buttonTintList = ColorStateList.valueOf(Color.parseColor("#FF0A84FF"))
                    toggle.setOnCheckedChangeListener { _, checked ->
                        if (syncingSettingsControls) return@setOnCheckedChangeListener
                        locked = checked
                        emitSettingsChanged()
                        if (locked) {
                            setSettingsExpanded(false)
                            setControlsExpanded(false)
                        } else {
                            applyAppearance()
                        }
                    }
                    addView(toggle)
                }
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(16) },
        )

        addView(
            settingButton(appContext, "恢复默认样式") {
                fontSize = 17f
                textColor = Color.WHITE
                locked = false
                applyAppearance()
                emitSettingsChanged()
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(44),
            ).apply { topMargin = dp(12) },
        )
    }

    private fun setControlsExpanded(expanded: Boolean) {
        if (expanded && locked) return
        val changing = controlsExpanded != expanded
        if (changing) root?.let { view ->
            // Layout and opacity move together; the glass window itself is
            // never scaled into a cached opaque rectangle.
            if (Build.VERSION.SDK_INT < 26 || android.animation.ValueAnimator.areAnimatorsEnabled()) {
                android.transition.TransitionManager.beginDelayedTransition(view,
                    android.transition.AutoTransition().apply { duration = 240L })
            }
        }
        controlsExpanded = expanded
        compactHeader?.visibility = if (expanded) View.VISIBLE else View.GONE
        compactDivider?.visibility = if (expanded) View.VISIBLE else View.GONE
        compactControls?.visibility = if (expanded) View.VISIBLE else View.GONE
        lyricStatusLabel?.visibility = View.GONE
        currentLine?.gravity = Gravity.CENTER
        nextLine?.gravity = Gravity.CENTER
        nextLine?.visibility = View.GONE

        root?.apply {
            setPadding(dp(if (expanded || settingsExpanded) 16 else 12),
                dp(if (expanded || settingsExpanded) 12 else 4),
                dp(if (expanded || settingsExpanded) 16 else 12),
                dp(if (expanded || settingsExpanded) 12 else 4))
            background = null
        }
        glassHost?.appearance(settingsExpanded)
        // The expanded controller is one composed surface. Keeping the lyric
        // stage unboxed removes the heavy nested-card look while the toolbar
        // below still gives the controls a clear tactile boundary.
        compactLyricsSurface?.background = null

        root?.let { view ->
            params?.let { layoutParams ->
                updateOverlayLayout(view, layoutParams)
            }
        }
    }

    private fun setSettingsExpanded(expanded: Boolean) {
        if (expanded && locked) return
        if (!isVisible || settingsExpanded == expanded) return
        if (expanded) setControlsExpanded(true)
        settingsExpanded = expanded
        compactContent?.visibility = if (expanded) View.GONE else View.VISIBLE
        settingsContent?.visibility = if (expanded) View.VISIBLE else View.GONE
        val screenWidth = context?.resources?.displayMetrics?.widthPixels ?: dp(360)
        params?.width = if (expanded) {
            overlayWidth(
                screenWidth,
                SETTINGS_OVERLAY_MAX_WIDTH_DP,
                SETTINGS_OVERLAY_SIDE_INSET_DP,
            )
        } else {
            overlayWidth(
                screenWidth,
                COMPACT_OVERLAY_MAX_WIDTH_DP,
                COMPACT_OVERLAY_SIDE_INSET_DP,
            )
        }
        params?.x = ((screenWidth - (params?.width ?: screenWidth)) / 2)
            .coerceAtLeast(0)
        root?.let { view -> params?.let { updateOverlayLayout(view, it) } }
        setControlsExpanded(controlsExpanded)
        applyAppearance()
    }

    private fun updateOverlayLayout(
        view: View,
        layoutParams: WindowManager.LayoutParams,
    ) {
        clampOverlayPosition(view, layoutParams)
        runCatching { glassHost?.update(layoutParams) }
        // Expanded controls and settings change a WRAP_CONTENT window's
        // measured height. Clamp again after that layout pass so the complete
        // surface remains reachable at the bottom edge too.
        view.post {
            if (!isVisible || root !== view || params !== layoutParams) return@post
            clampOverlayPosition(view, layoutParams)
            runCatching { glassHost?.update(layoutParams) }
        }
    }

    private fun clampOverlayPosition(
        view: View,
        layoutParams: WindowManager.LayoutParams,
    ) {
        val appContext = context ?: return
        val metrics = appContext.resources.displayMetrics
        val edgeInset = dp(OVERLAY_DRAG_EDGE_INSET_DP)
        val overlayWidth = view.width.takeIf { it > 0 }
            ?: layoutParams.width.takeIf { it > 0 }
            ?: 0
        val overlayHeight = view.height.takeIf { it > 0 }
            ?: view.measuredHeight.takeIf { it > 0 }
            ?: 0
        val topInset = systemBarInset("status_bar_height") + edgeInset
        val bottomInset = systemBarInset("navigation_bar_height") + edgeInset
        val maxX = (metrics.widthPixels - overlayWidth - edgeInset)
            .coerceAtLeast(edgeInset)
        val maxY = (metrics.heightPixels - overlayHeight - bottomInset)
            .coerceAtLeast(topInset)

        layoutParams.x = layoutParams.x.coerceIn(edgeInset, maxX)
        layoutParams.y = layoutParams.y.coerceIn(topInset, maxY)
    }

    private fun systemBarInset(resourceName: String): Int {
        val resources = context?.resources ?: return 0
        val resourceId = resources.getIdentifier(resourceName, "dimen", "android")
        return if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else 0
    }

    private fun overlayWidth(
        screenWidth: Int,
        maxWidthDp: Int,
        sideInsetDp: Int,
    ): Int = minOf(
        dp(maxWidthDp),
        (screenWidth - dp(sideInsetDp * 2)).coerceAtLeast(dp(1)),
    )

    private fun applyAppearance() {
        currentLine?.textSize = fontSize
        nextLine?.textSize = (fontSize - 4f).coerceAtLeast(11f)
        currentLine?.setTextColor(textColor)
        nextLine?.setTextColor((textColor and 0x00FFFFFF) or (145 shl 24))
        currentLine?.setShadowLayer(
            dp(1).toFloat(),
            0f,
            dp(1).toFloat(),
            Color.parseColor("#8F000000"),
        )
        nextLine?.setShadowLayer(
            dp(1).toFloat(),
            0f,
            dp(1).toFloat(),
            Color.parseColor("#73000000"),
        )
        settingsPreview?.text = currentLine?.text ?: "让音乐停留在桌面"
        settingsPreview?.textSize = fontSize
        settingsPreview?.setTextColor(textColor)
        fontSizeValue?.text = "${fontSize.roundToInt()}sp"
        lockButton?.background = if (locked) {
            roundedBackground("#330A84FF", "#550A84FF", 999f)
        } else {
            roundedBackground("#00000000", "#00000000", 999f)
        }
        lockButton?.setCompoundDrawablesRelativeWithIntrinsicBounds(
            if (locked) R.drawable.ic_overlay_lock else R.drawable.ic_overlay_unlock,
            0,
            0,
            0,
        )
        lockButton?.contentDescription =
            if (locked) "桌面歌词已锁定" else "锁定桌面歌词"
        lockStateLabel?.text = if (locked) "已锁定" else "可拖动"
        lockStateLabel?.setTextColor(
            if (locked) Color.parseColor("#FF9EB0FF") else Color.parseColor("#CCFFFFFF"),
        )
        lockStateLabel?.background = null
        settingsButton?.isEnabled = !locked
        settingsButton?.alpha = if (locked) .28f else 1f
        favoriteButton?.setCompoundDrawablesRelativeWithIntrinsicBounds(
            if (favorite) {
                R.drawable.ic_overlay_favorite_filled
            } else {
                R.drawable.ic_overlay_favorite
            },
            0,
            0,
            0,
        )
        favoriteButton?.compoundDrawableTintList = ColorStateList.valueOf(
            // Match Flutter's shared heart color for the native lyrics action.
            if (favorite) Color.parseColor("#FFCC3F56") else Color.WHITE,
        )
        favoriteButton?.contentDescription =
            if (favorite) "取消收藏当前歌曲" else "收藏当前歌曲"

        syncingSettingsControls = true
        fontSizeSeek?.progress = (fontSize - 14f).roundToInt()
        lockSwitch?.isChecked = locked
        syncingSettingsControls = false
        colorButtons.forEach { (color, button) ->
            val selected = (color and 0x00FFFFFF) == (textColor and 0x00FFFFFF)
            button.text = if (selected) "✓" else ""
            button.background = colorDotBackground(color, selected)
        }

        val layoutParams = params
        val overlay = root
        if (layoutParams != null && overlay != null) {
            layoutParams.flags = if (locked) {
                layoutParams.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
            } else {
                layoutParams.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
            }
            runCatching { glassHost?.update(layoutParams) }
        }
    }

    private fun emitAction(action: String) {
        actionSink?.invoke(mapOf("action" to action))
    }

    private fun emitSettingsChanged() {
        actionSink?.invoke(
            mapOf(
                "action" to "settingsChanged",
                "fontSize" to fontSize.toDouble(),
                "textColor" to String.format("#%08X", textColor.toLong() and 0xFFFFFFFFL),
                "locked" to locked,
            ),
        )
    }

    private fun lyricTextView(appContext: Context, size: Float, bold: Boolean) =
        TextView(appContext).apply {
            textSize = size
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            maxLines = 2
            includeFontPadding = false
            setLineSpacing(dp(2).toFloat(), 1.04f)
            typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        }

    private fun controlButton(appContext: Context, label: String, action: String) =
        TextView(appContext).apply {
            text = label
            textSize = 1f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            includeFontPadding = false
            setCompoundDrawablesRelativeWithIntrinsicBounds(
                when (action) {
                    "previous" -> R.drawable.ic_overlay_previous
                    "playPause" -> if (playing) {
                        R.drawable.ic_overlay_pause
                    } else {
                        R.drawable.ic_overlay_play
                    }
                    "next" -> R.drawable.ic_overlay_next
                    "settings" -> R.drawable.ic_overlay_settings
                    "favorite" -> if (favorite) {
                        R.drawable.ic_overlay_favorite_filled
                    } else {
                        R.drawable.ic_overlay_favorite
                    }
                    "lock" -> if (locked) {
                        R.drawable.ic_overlay_lock
                    } else {
                        R.drawable.ic_overlay_unlock
                    }
                    "close" -> R.drawable.ic_overlay_close
                    else -> 0
                },
                0,
                0,
                0,
            )
            compoundDrawableTintList = ColorStateList.valueOf(
                when (action) {
                    "favorite" -> if (favorite) {
                        Color.parseColor("#FFCC3F56")
                    } else {
                        Color.WHITE
                    }
                    else -> Color.WHITE
                },
            )
            contentDescription = when (action) {
                "previous" -> "上一首"
                "playPause" -> "播放或暂停"
                "next" -> "下一首"
                "settings" -> "设置歌词字体大小和颜色"
                "favorite" -> if (favorite) "取消收藏当前歌曲" else "收藏当前歌曲"
                "lock" -> "锁定桌面歌词"
                "close" -> "关闭桌面歌词"
                else -> action
            }
            background = roundedBackground("#00000000", "#00000000", 999f)
            layoutParams = LinearLayout.LayoutParams(
                dp(if (action == "playPause") 50 else 48),
                dp(if (action == "playPause") 50 else 48),
            ).apply {
                marginStart = dp(if (action == "playPause") 3 else 1)
                marginEnd = dp(if (action == "playPause") 3 else 1)
            }
            setOnTouchListener { view, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> view.animate()
                        .scaleX(.93f)
                        .scaleY(.93f)
                        .alpha(.72f)
                        .setDuration(70L)
                        .start()
                    MotionEvent.ACTION_UP,
                    MotionEvent.ACTION_CANCEL -> view.animate()
                        .scaleX(1f)
                        .scaleY(1f)
                        .alpha(1f)
                        .setDuration(140L)
                        .start()
                }
                false
            }
            setOnClickListener {
                when (action) {
                    "close" -> {
                        emitAction(action)
                        hide()
                    }
                    "settings" -> if (!locked) setSettingsExpanded(true)
                    "favorite" -> emitAction("toggleFavorite")
                    "lock" -> {
                        if (!locked) {
                            locked = true
                            emitSettingsChanged()
                            if (settingsExpanded) setSettingsExpanded(false)
                            setControlsExpanded(false)
                            Toast.makeText(
                                appContext,
                                "桌面歌词已锁定，可在灵动岛或通知中心的音乐面板中点击“词”解锁",
                                Toast.LENGTH_LONG,
                            ).show()
                            applyAppearance()
                        }
                    }
                    else -> emitAction(action)
                }
            }
        }

    private fun settingText(
        appContext: Context,
        label: String,
        size: Float,
        color: Int,
        bold: Boolean = false,
    ) = TextView(appContext).apply {
        text = label
        textSize = size
        setTextColor(color)
        typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
    }

    private fun settingButton(appContext: Context, label: String, onClick: () -> Unit) =
        TextView(appContext).apply {
            text = label
            textSize = 13f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            background = roundedBackground("#1AFFFFFF", "#30FFFFFF", 999f)
            setOnClickListener { onClick() }
        }

    private fun colorDotBackground(color: Int, selected: Boolean) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(color)
        setStroke(dp(if (selected) 3 else 1), if (selected) Color.WHITE else Color.parseColor("#35FFFFFF"))
    }

    private fun roundedBackground(fill: String, stroke: String, radius: Float) =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(radius.roundToInt()).toFloat()
            setColor(Color.parseColor(fill))
            setStroke(dp(1), Color.parseColor(stroke))
        }

    private fun gradientBackground(colors: IntArray, stroke: Int, radius: Float) =
        GradientDrawable(GradientDrawable.Orientation.TL_BR, colors).apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(radius.roundToInt()).toFloat()
            setStroke(dp(1), stroke)
        }

    private fun dividerBackground() = GradientDrawable(
        GradientDrawable.Orientation.LEFT_RIGHT,
        intArrayOf(
            Color.parseColor("#00FFFFFF"),
            Color.parseColor("#607790FF"),
            Color.parseColor("#00FFFFFF"),
        ),
    )

    private fun dp(value: Int): Int {
        val density = context?.resources?.displayMetrics?.density ?: 1f
        return (value * density).roundToInt()
    }

    private const val LYRIC_EXIT_DURATION_MS = 120L
    private const val LYRIC_ENTER_DURATION_MS = 220L
}
