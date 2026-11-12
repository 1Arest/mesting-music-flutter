import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_mine_widgets.dart';
import 'support/release_147_qa.dart' show load147IconFonts;

const _capture177 = bool.fromEnvironment('CAPTURE_177');

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (_capture177) {
      await load147IconFonts();
      await (FontLoader('SodaQA177')..addFont(
            File(
              'C:/Windows/Fonts/msyh.ttc',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });

  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets(
        'official stats retain independent targets, dark=$dark large=$large',
        (tester) async {
          tester.view.physicalSize = Size(large ? 320 : 390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final taps = <String>[];
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
                fontFamily: _capture177 ? 'SodaQA177' : null,
              ),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(large ? 320 : 390, 844),
                  textScaler: TextScaler.linear(large ? 2 : 1),
                ),
                child: RepaintBoundary(
                  key: boundary,
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: QishuiMineHeader(
                        nickname: '测试账号',
                        avatar: '',
                        playlists: const [],
                        following: 18,
                        followers: 27,
                        likes: 93,
                        listeningLabel: '123 小时 45 分钟',
                        onFollowing: () => taps.add('following'),
                        onFollowers: () => taps.add('followers'),
                        onLikes: () => taps.add('likes'),
                        onListening: () => taps.add('listening'),
                        onAccount: () => taps.add('account'),
                        onMembership: () {},
                        onEffects: () {},
                        onSwitchPlatform: () {},
                        onSettings: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final label in ['18 关注', '27 粉丝', '93 获赞']) {
            await tester.ensureVisible(find.text(label));
            await tester.tap(find.text(label));
          }
          expect(taps, ['following', 'followers', 'likes']);
          await tester.ensureVisible(
            find.byKey(const ValueKey('qishui-official-listening')),
          );
          await tester.tap(
            find.byKey(const ValueKey('qishui-official-listening')),
          );
          expect(taps.last, 'listening');
          expect(taps, isNot(contains('account')));
          if (_capture177) {
            await tester.pumpAndSettle();
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 1);
              try {
                final bytes = (await image.toByteData(
                  format: ui.ImageByteFormat.png,
                ))!;
                final target = File(
                  '.codex-artifacts/2026-11-07-release177/ui/header-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}.png',
                );
                await target.parent.create(recursive: true);
                await target.writeAsBytes(
                  bytes.buffer.asUint8List(
                    bytes.offsetInBytes,
                    bytes.lengthInBytes,
                  ),
                );
              } finally {
                image.dispose();
              }
            });
          }
        },
      );
    }
  }

  testWidgets(
    'unknown official values remain unknown rather than fabricated zero',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: QishuiMineHeader(
                nickname: '测试',
                avatar: '',
                playlists: const [],
                onAccount: () {},
                onMembership: () {},
                onEffects: () {},
                onSwitchPlatform: () {},
                onSettings: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('— 关注'), findsOneWidget);
      expect(find.text('— 粉丝'), findsOneWidget);
      expect(find.text('— 获赞'), findsOneWidget);
      expect(find.text('0 关注'), findsNothing);
    },
  );
}
