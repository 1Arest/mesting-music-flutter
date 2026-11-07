import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/lyrics_overlay_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('原生桌面歌词通道缺失时安全降级而不抛未处理异常', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final bridge = LyricsOverlayBridge();

    expect(await bridge.canDrawOverlays(), isFalse);
    expect(await bridge.notificationPermissionGranted(), isFalse);
    expect(await bridge.show(const {'current': '测试'}), isFalse);
    await bridge.requestPermission();
    await bridge.requestNotificationPermission();
    await bridge.update(const {'current': '测试'});
    await bridge.hide();
    await bridge.bringAppToFront();
  });

  test('桌面歌词首次显示时直接携带当前歌词而不是准备中占位', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final bridge = _FakeLyricsOverlayBridge();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        lyricsOverlayBridgeProvider.overrideWithValue(bridge),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(lyricsOverlayProvider.notifier)
        .show(current: '从前从前', next: '有个人爱你很久', playing: true);

    expect(container.read(lyricsOverlayProvider).visible, isTrue);
    expect(bridge.lastShow?['current'], '从前从前');
    expect(bridge.lastShow?['next'], '有个人爱你很久');
    expect(bridge.lastShow?['playing'], isTrue);
    expect(bridge.lastShow?['favorite'], isFalse);
    expect(bridge.lastShow?['next'], isNot('歌词准备中'));
  });

  test('首次授权悬浮窗后保留授权前的真实歌词', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final bridge = _FakeLyricsOverlayBridge()..permitted = false;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        lyricsOverlayBridgeProvider.overrideWithValue(bridge),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(lyricsOverlayProvider.notifier)
        .show(current: '窗外的麻雀', next: '在电线杆上多嘴', playing: true);
    expect(bridge.lastShow, isNull);

    bridge.permitted = true;
    await container.read(lyricsOverlayProvider.notifier).refreshPermissions();

    expect(bridge.lastShow?['current'], '窗外的麻雀');
    expect(bridge.lastShow?['next'], '在电线杆上多嘴');
  });

  test('通知栏已直接拉起授权页时只暂存歌词且授权返回后自动显示', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final bridge = _FakeLyricsOverlayBridge()..permitted = false;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        lyricsOverlayBridgeProvider.overrideWithValue(bridge),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(lyricsOverlayProvider.notifier);
    controller.prepareShowAfterPermission(
      current: '风吹过的地方',
      next: '仍然留着回声',
      playing: true,
    );

    expect(bridge.permissionRequestCount, 0);
    expect(bridge.lastShow, isNull);

    bridge.permitted = true;
    bridge.onAction?.call({
      'action': 'notificationPermissionResult',
      'granted': true,
    });
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(bridge.permissionRequestCount, 0);
    expect(bridge.lastShow?['current'], '风吹过的地方');
    expect(bridge.lastShow?['next'], '仍然留着回声');
    expect(container.read(lyricsOverlayProvider).visible, isTrue);
  });

  test('系统桌面设置修改后会同步并保存歌词样式', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final bridge = _FakeLyricsOverlayBridge();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        lyricsOverlayBridgeProvider.overrideWithValue(bridge),
      ],
    );
    addTearDown(container.dispose);

    container.read(lyricsOverlayProvider);
    bridge.onAction?.call({
      'action': 'settingsChanged',
      'fontSize': 24,
      'textColor': '#FFFF7FA0',
      'locked': true,
    });
    await Future<void>.delayed(Duration.zero);

    final settings = container.read(lyricsOverlayProvider);
    expect(settings.fontSize, 24);
    expect(settings.textColor, '#FFFF7FA0');
    expect(settings.locked, isTrue);
    expect(preferences.getDouble('lyrics_overlay_font_size'), 24);
    expect(preferences.getString('lyrics_overlay_text_color'), '#FFFF7FA0');
    expect(preferences.getBool('lyrics_overlay_locked'), isTrue);
  });

  test('通知栏解锁桌面歌词时保留当前歌词内容', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final bridge = _FakeLyricsOverlayBridge();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        lyricsOverlayBridgeProvider.overrideWithValue(bridge),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(lyricsOverlayProvider.notifier);
    await controller.show(current: '瓶身描绘的牡丹', next: '一如你初妆', playing: true);
    await controller.setLocked(true);
    await controller.setLocked(false);

    expect(bridge.lastUpdate?['current'], '瓶身描绘的牡丹');
    expect(bridge.lastUpdate?['next'], '一如你初妆');
    expect(bridge.lastUpdate?['playing'], isTrue);
    expect(bridge.lastUpdate?['locked'], isFalse);
    expect(container.read(lyricsOverlayProvider).visible, isTrue);
  });

  test('桌面歌词收藏操作复用正式收藏事件并同步收藏状态', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final bridge = _FakeLyricsOverlayBridge();
    final handler = _FakeAudioHandler();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        lyricsOverlayBridgeProvider.overrideWithValue(bridge),
        audioHandlerProvider.overrideWithValue(handler),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(lyricsOverlayProvider.notifier);
    await controller.show(
      current: '纯音乐，请欣赏',
      next: '',
      playing: true,
      favorite: true,
    );

    expect(bridge.lastShow?['favorite'], isTrue);
    bridge.onAction?.call({'action': 'toggleFavorite'});
    await Future<void>.delayed(Duration.zero);

    expect(
      handler.lastCustomAction,
      MestingAudioHandler.notificationToggleFavoriteAction,
    );
  });
}

class _FakeAudioHandler extends MestingAudioHandler {
  _FakeAudioHandler() : super(tracks: const []);

  String? lastCustomAction;

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    lastCustomAction = name;
  }
}

class _FakeLyricsOverlayBridge extends LyricsOverlayBridge {
  Map<String, Object>? lastShow;
  Map<String, Object>? lastUpdate;
  bool permitted = true;
  int permissionRequestCount = 0;

  @override
  Future<bool> canDrawOverlays() async => permitted;

  @override
  Future<bool> notificationPermissionGranted() async => true;

  @override
  Future<void> requestPermission() async {
    permissionRequestCount += 1;
  }

  @override
  Future<bool> show(Map<String, Object> payload) async {
    lastShow = payload;
    return true;
  }

  @override
  Future<void> update(Map<String, Object> payload) async {
    lastUpdate = payload;
  }

  @override
  Future<void> hide() async {}
}
