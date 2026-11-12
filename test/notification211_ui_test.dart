import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/notifications/notification_bridge.dart';
import 'package:mesting_music/features/notifications/notification_pages.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/beta_control_scope.dart';
import 'support/ui_fix_capture.dart';

class _PreviewBridge extends MusicNotificationBridge {
  final settings = <String, Object?>{};
  @override
  bool get supported => true;
  @override
  Future<Map<String, dynamic>> state() async => {
    'permission': true,
    'scheduled': true,
    'json': jsonEncode({
      'settings': settings,
      'inbox': [
        {
          'id': 'netease-message',
          'platform': 'netease',
          'kind': 'privateMessage',
          'title': '朋友发来消息',
          'body': '刚听到一首歌，想和你分享。',
          'time': 1700000000001,
        },
        {
          'id': 'kugou-artist',
          'platform': 'kugou',
          'kind': 'artist',
          'title': '关注歌手有新作品',
          'body': '你关注的歌手发布了新作品。',
          'time': 1700000000000,
        },
      ],
    }),
  };
  @override
  Future<T?> call<T>(String method, [Map<String, Object?>? args]) async {
    if (method == 'settings') {
      settings.addAll(Map<String, Object?>.from(args!['values'] as Map));
    }
    return null;
  }
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    await initializeUiFixCapture();
  });
  for (final size in [const Size(390, 844), const Size(1024, 768)]) {
    for (final dark in [false, true]) {
      for (final inbox in [false, true]) {
        testWidgets(
          'notification surface ${inbox ? 'inbox' : 'settings'} ${size.width} dark=$dark',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final bridge = _PreviewBridge();
            var theme = buildMestingTheme(
              musicThemePresetById(dark ? 'classic-dark' : 'classic'),
            );
            if (uiFixCaptureDirectory.isNotEmpty) {
              theme = theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'UiFixCJK'),
                listTileTheme: theme.listTileTheme.copyWith(
                  titleTextStyle: theme.listTileTheme.titleTextStyle?.copyWith(
                    fontFamily: 'UiFixCJK',
                  ),
                  subtitleTextStyle: theme.listTileTheme.subtitleTextStyle
                      ?.copyWith(fontFamily: 'UiFixCJK'),
                ),
              );
            }
            await tester.pumpWidget(
              BetaControlScope(
                apple: true,
                child: RepaintBoundary(
                  key: uiFixCaptureKey,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: theme,
                    home: inbox
                        ? MusicNotificationInboxPage(
                            bridge: bridge,
                            noticeId: 'netease-message',
                          )
                        : MusicNotificationSettingsPage(bridge: bridge),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (!inbox) {
              expect(find.byType(CupertinoSwitch), findsWidgets);
              await tester.tap(find.byType(CupertinoSwitch).first);
              await tester.pumpAndSettle();
              expect(bridge.settings['enabled'], false);
              await tester.tap(find.byType(CupertinoSwitch).first);
              await tester.pumpAndSettle();
              expect(bridge.settings['enabled'], true);
            } else {
              expect(find.textContaining('刚听到一首歌'), findsOneWidget);
              expect(find.textContaining('关注歌手有新作品'), findsOneWidget);
            }
            await captureUiFix(
              tester,
              'notification-${inbox ? 'inbox' : 'settings'}-${size.width.toInt()}-${dark ? 'dark' : 'light'}',
            );
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
          },
        );
      }
    }
  }
  testWidgets('platform inbox filters the other retained account', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MusicNotificationInboxPage(
          bridge: _PreviewBridge(),
          platform: 'netease',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('刚听到一首歌'), findsOneWidget);
    expect(find.textContaining('关注歌手有新作品'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
