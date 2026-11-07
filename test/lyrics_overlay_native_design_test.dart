import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        'android/app/src/main/kotlin/com/mesting/mesting_music/MainActivity.kt',
      ).readAsStringSync() +
      File(
        'android/app/src/main/kotlin/com/mesting/mesting_music/LyricsOverlayController.kt',
      ).readAsStringSync() +
      File(
        'android/app/src/main/kotlin/com/mesting/mesting_music/LyricsOverlayGlassHost.kt',
      ).readAsStringSync();
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final audioHandlerSource = File(
    'lib/core/audio/mesting_audio_handler.dart',
  ).readAsStringSync();
  final notificationLyricsIcon = File(
    'android/app/src/main/res/drawable/ic_notification_lyrics.xml',
  ).readAsStringSync();
  final notificationLyricsOnIcon = File(
    'android/app/src/main/res/drawable/ic_notification_lyrics_on.xml',
  ).readAsStringSync();
  final overlayControlIcons = <String, String>{
    for (final name in <String>[
      'previous',
      'next',
      'play',
      'pause',
      'lock',
      'unlock',
      'close',
      'settings',
      'favorite',
      'favorite_filled',
    ])
      name: File(
        'android/app/src/main/res/drawable/ic_overlay_$name.xml',
      ).readAsStringSync(),
  };

  test('通知中心桌面歌词操作显示词字而非消息气泡', () {
    for (final icon in <String>[
      notificationLyricsIcon,
      notificationLyricsOnIcon,
    ]) {
      expect(icon, contains('“词” glyph'));
      expect(icon, contains('M4.2,4.3L6.6,6.1'));
      expect(icon, isNot(contains('M4,4H20C21.1')));
    }
    expect(notificationLyricsOnIcon, contains('android:strokeWidth="2.2"'));
  });

  test('桌面歌词使用有界系统背景模糊与可读降级材质', () {
    expect(source, contains('"Mesting Music"'));
    expect(source, contains('R.drawable.mesting_mark_foreground'));
    expect(source, contains('setBackgroundBlurRadius'));
    expect(source, contains('isCrossWindowBlurEnabled'));
    expect(source, contains('Color.parseColor("#EB35404B")'));
    expect(source, contains('Color.parseColor("#FF0A84FF")'));
    expect(source, isNot(contains('#FFFF8DA8')));
    expect(source, isNot(contains('#FFFF668A')));
    expect(source, isNot(contains('Color.parseColor("#42FF9CB4")')));
  });

  test('歌词区不再嵌套笨重卡片且控制项收入统一工具栏', () {
    expect(source, contains('compactLyricsSurface = this'));
    expect(source, contains('compactDivider = content.getChildAt(2)'));
    expect(source, contains('content.getChildAt(3) as? LinearLayout'));
    expect(source, contains('compactDivider?.visibility'));
    expect(source, contains('lyricStatusLabel?.visibility'));
    expect(source, contains('compactLyricsSurface?.background = null'));
    expect(source, contains('dividerBackground()'));
    expect(source, contains('Color.parseColor("#607790FF")'));
    expect(source, contains('LinearLayout.LayoutParams.WRAP_CONTENT'));
    expect(source, contains('currentLine?.gravity'));
    expect(source, contains('setLineSpacing(dp(2).toFloat(), 1.04f)'));
    expect(source, contains('dp(if (action == "playPause") 50 else 48)'));
    expect(source, isNot(contains('Color.parseColor("#CC292C37")')));
    expect(source, contains('LinearLayout.LayoutParams(dp(44), dp(44))'));
  });

  test('控制栏使用可着色矢量图标而非字形伪图标', () {
    for (final entry in overlayControlIcons.entries) {
      expect(entry.value, contains('<vector'), reason: entry.key);
      expect(entry.value, contains('android:pathData='), reason: entry.key);
      expect(source, contains('R.drawable.ic_overlay_${entry.key}'));
    }
    expect(source, isNot(contains('controlButton(appContext, "‹"')));
    expect(source, isNot(contains('controlButton(appContext, "›"')));
    expect(source, isNot(contains('controlButton(appContext, "Aa"')));
    expect(source, isNot(contains('playButton?.text =')));
  });

  test('展开面板按确认稿提供字体设置和真实收藏功能', () {
    expect(
      source,
      contains('settingsButton = controlButton(appContext, "", "settings")'),
    );
    expect(
      source,
      contains('favoriteButton = controlButton(appContext, "", "favorite")'),
    );
    expect(source, contains('"favorite" -> emitAction("toggleFavorite")'));
    expect(source, contains('R.drawable.ic_overlay_favorite_filled'));
    expect(source, contains('"设置歌词字体大小和颜色"'));
    expect(source, contains('"收藏当前歌曲"'));
    expect(source, contains('"取消收藏当前歌曲"'));
  });

  test('桌面歌词在窄边距内使用更长的紧凑控制面板', () {
    expect(source, contains('COMPACT_OVERLAY_MAX_WIDTH_DP = 376'));
    expect(source, contains('COMPACT_OVERLAY_SIDE_INSET_DP = 6'));
    expect(source, contains('val compactWidth = overlayWidth('));
    expect(
      source,
      contains('x = ((screenWidth - compactWidth) / 2).coerceAtLeast(0)'),
    );
    expect(source, contains('private fun overlayWidth('));
    expect(source, isNot(contains('dp(344),')));
    expect(source, isNot(contains('x = dp(22)')));
  });

  test('桌面歌词拖动和尺寸变化后都限制在系统安全边缘内', () {
    expect(source, contains('OVERLAY_DRAG_EDGE_INSET_DP = 6'));
    expect(source, contains('private fun clampOverlayPosition('));
    expect(source, contains('layoutParams.x = layoutParams.x.coerceIn('));
    expect(source, contains('layoutParams.y = layoutParams.y.coerceIn('));
    expect(source, contains('systemBarInset("status_bar_height")'));
    expect(source, contains('systemBarInset("navigation_bar_height")'));
    expect(source, contains('clampOverlayPosition(this, layoutParams)'));
    expect(source, contains('private fun updateOverlayLayout('));
    expect(source, contains('view.post {'));
  });

  test('未锁定与锁定状态使用对应图标并提示通知中心解锁路径', () {
    expect(
      source,
      contains(
        'if (locked) R.drawable.ic_overlay_lock else '
        'R.drawable.ic_overlay_unlock',
      ),
    );
    expect(source, contains('Toast.LENGTH_LONG'));
    expect(source, contains('灵动岛或通知中心的音乐面板中点击“词”解锁'));
  });

  test('字体大小与颜色设置保留即时预览、调色和恢复默认', () {
    expect(source, contains('settingText(appContext, "桌面歌词", 18f'));
    expect(source, contains('settingText(appContext, "字体颜色", 14f'));
    expect(source, contains('settingsPreview = settingText'));
    expect(source, contains('colorPalette.toList().chunked(4)'));
    expect(source, contains('glassHost?.appearance(settingsExpanded)'));
    expect(source, contains('Color.parseColor("#20FFFFFF")'));
    expect(source, contains('settingButton(appContext, "恢复默认样式")'));
  });

  test('桌面歌词按钮向系统提供完整中文语义', () {
    for (final label in <String>[
      '上一首',
      '播放或暂停',
      '下一首',
      '设置歌词字体大小和颜色',
      '收藏当前歌曲',
      '取消收藏当前歌曲',
      '锁定桌面歌词',
      '关闭桌面歌词',
    ]) {
      expect(source, contains('"$label"'));
    }
  });

  test('通知栏首次开启桌面歌词会直接进入原生悬浮窗授权链路', () {
    expect(audioHandlerSource, contains("'requestPermissionFromNotification'"));
    expect(audioHandlerSource, contains("'permissionRequestLaunched'"));
    expect(source, contains('LyricsOverlayPermissionActivity::class.java'));
    expect(source, contains('PendingIntent.getActivity('));
    expect(source, contains('setPendingIntentBackgroundActivityStartMode'));
    expect(source, contains('MODE_BACKGROUND_ACTIVITY_START_ALLOW_ALWAYS'));
    expect(source, contains('Settings.ACTION_MANAGE_OVERLAY_PERMISSION'));
    expect(source, contains('"notificationPermissionResult"'));
    expect(
      manifest,
      contains('android:name=".LyricsOverlayPermissionActivity"'),
    );
    expect(manifest, contains('android:excludeFromRecents="true"'));
  });
}
