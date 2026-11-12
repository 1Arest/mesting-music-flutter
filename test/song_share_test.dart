import 'package:mesting_music/shared/widgets/beta_selection_controls.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/player/sharing/song_share.dart';
import 'package:mesting_music/features/player/sharing/song_share_sheet.dart';
import 'package:mesting_music/shared/models/track.dart';

Track song({
  String id = 'local',
  TrackSource source = TrackSource.local,
  String url = '',
  String cover = '',
}) => Track(
  id: id,
  title: '一起听这首歌',
  artist: '分享给每一位朋友',
  album: '',
  duration: const Duration(minutes: 3),
  audioAsset: 'file:///private/song.mp3',
  coverAsset: cover,
  lyricsAsset: '',
  source: source,
  externalUrl: url,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('only public catalogue links leave the device', () {
    for (final url in [
      '',
      'file:///private/song.mp3',
      'content://audio/1',
      'mesting-platform://kugou/private',
      'https://token:secret@example.com/song',
      'https:///song',
    ]) {
      expect(songShareUrl(song(url: url)), isNull);
    }
    expect(
      songShareUrl(song(url: 'https://music.163.com/#/song?id=123')),
      'https://music.163.com/#/song?id=123',
    );
  });

  test('downloaded catalogue tracks retain platform identity for sharing', () {
    expect(
      songShareUrl(song(id: 'netease_123', source: TrackSource.netease)),
      'https://music.163.com/#/song?id=123',
    );
    const hash = '0123456789abcdef0123456789abcdef';
    expect(
      songShareUrl(song(id: 'kugou_$hash', source: TrackSource.kugou)),
      'https://www.kugou.com/song/#hash=$hash',
    );
    expect(
      songShareUrl(song(id: 'kugou_bad', source: TrackSource.kugou)),
      isNull,
    );
  });

  testWidgets('poster exports a full resolution PNG even without artwork', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final png = await generateSongPoster(song());
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 1080);
      expect(frame.image.height, 1704);
      frame.image.dispose();
      codec.dispose();
    });
  });

  testWidgets(
    'local share sheet scrolls at large text sizes and disables link sharing',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(body: SongShareSheet(track: song())),
            ),
          ),
        ),
      );
      final button = tester.widget<BetaActionButton>(
        find.widgetWithText(BetaActionButton, '分享链接给微信好友'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('这首歌暂无公开链接，可以生成海报分享。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'generated poster saves the preview PNG through the gallery bridge',
    (tester) async {
      const channel = MethodChannel('com.mesting.music/media_library');
      MethodCall? received;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        received = call;
        return 'content://media/images/123';
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: Scaffold(body: SongShareSheet(track: song())),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('生成分享海报'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存海报'));
      await tester.tap(find.text('保存海报'));
      await tester.pumpAndSettle();
      expect(received?.method, 'saveImage');
      final arguments = received!.arguments as Map;
      expect(arguments['mimeType'], 'image/png');
      expect((arguments['bytes'] as List).take(8), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
      expect(find.text('海报已保存到相册'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'WeChat receives only the link and reports unavailable installs',
    (tester) async {
      const channel = MethodChannel('com.mesting.music/share');
      MethodCall? received;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        received = call;
        throw PlatformException(
          code: 'wechat_unavailable',
          message: '请先安装微信，再分享给好友',
        );
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: Scaffold(
              body: SongShareSheet(
                track: song(id: 'netease_123', source: TrackSource.netease),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('分享链接给微信好友'));
      await tester.pumpAndSettle();
      expect(received?.method, 'shareToWeChat');
      expect(received?.arguments, {
        'url': 'https://music.163.com/#/song?id=123',
      });
      expect(find.text('请先安装微信，再分享给好友'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
