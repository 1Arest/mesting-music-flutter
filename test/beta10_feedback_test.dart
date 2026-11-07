import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/shared/widgets/beta_anchored_menu.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:mesting_music/features/auth/presentation/beta_sign_out_dialog.dart';
import 'package:mesting_music/features/experience/presentation/player_content_transition.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';

const _capture = ValueKey('feedback-capture');
void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('EXPORT_BETA_SCREENSHOTS')) {
      for (final family in ['BetaQACJK', 'Roboto']) {
        await (FontLoader(family)..addFont(
              File(
                'C:/Windows/Fonts/msyh.ttc',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
      await (FontLoader('MaterialIcons')..addFont(
            File(
              'D:/flutter/mesting-beta5/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    if (const bool.fromEnvironment('EXPORT_BETA_SCREENSHOTS')) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'BetaQACJK'),
      );
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: _capture,
        child: MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            backgroundColor: theme.colorScheme.surface,
            body: SafeArea(child: page),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('EXPORT_BETA_SCREENSHOTS')) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File(
        '${const String.fromEnvironment('BETA10_CAPTURE_DIR')}/$name.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  for (final scale in [1.0, 1.6]) {
    for (final dark in [false, true]) {
      testWidgets(
        'menus match their actual triggers at $scale text, dark=$dark',
        (tester) async {
          var selected = '';
          await pump(
            tester,
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  BetaAnchoredMenu<String>(
                    tooltip: '评论排序',
                    value: '最热',
                    values: const ['最热', '最新', '最早'],
                    label: (s) => s,
                    onSelected: (s) => selected = s,
                  ),
                  const SizedBox(width: 8),
                  BetaAnchoredMenu<String>(
                    tooltip: '评论范围',
                    value: '全部',
                    values: const ['全部', '歌手', '我的'],
                    label: (s) => s,
                    onSelected: (s) => selected = s,
                  ),
                ],
              ),
            ),
            dark: dark,
            scale: scale,
          );
          for (final entry in [('评论排序', '最新'), ('评论范围', '歌手')]) {
            final trigger = find.byTooltip(entry.$1);
            final width = tester.getSize(trigger).width;
            await tester.tap(trigger);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            final item = find.byWidgetPredicate(
              (w) => DistributionChannel.isBeta
                  ? w is ListTile &&
                        w.title is Text &&
                        (w.title as Text).data == entry.$2
                  : w is PopupMenuItem<String> && w.value == entry.$2,
            );
            expect(tester.getSize(item).width, closeTo(width, .1));
            expect(tester.takeException(), isNull);
            if (entry.$1 == '评论排序') {
              final other = tester.getTopLeft(find.byTooltip('评论范围')).dx;
              expect(tester.getRect(item).right, lessThanOrEqualTo(other));
            }
            await capture(
              tester,
              'menu-${entry.$1 == '评论排序' ? 'sort' : 'scope'}-$scale-${dark ? 'dark' : 'light'}',
            );
            await tester.tap(find.text(entry.$2).last);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            expect(selected, entry.$2);
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets(
    'logout shows a spinner, deduplicates taps, and keeps a recoverable failure',
    (tester) async {
      final pending = Completer<void>();
      var requests = 0;
      await pump(
        tester,
        BetaSignOutDialog(
          onConfirm: () {
            requests++;
            return pending.future;
          },
        ),
      );
      final button = find.byKey(const ValueKey('beta10-confirm-sign-out'));
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<BetaGlassButton>(button).loading, true);
      expect(find.byType(BetaActivityIndicator), findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      expect(requests, 1);
      await capture(tester, 'mesting-logout-pending');
      pending.completeError(StateError('offline'));
      await tester.pump();
      expect(find.text('退出未完成，请重试'), findsOneWidget);
      expect(tester.widget<BetaGlassButton>(button).loading, false);
      expect(tester.takeException(), isNull);
      await capture(tester, 'mesting-logout-error');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'content transitions have opposite previous-next movement and retain transport',
    (tester) async {
      var direction = 1.0;
      var recording = 'A';
      late StateSetter update;
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Column(
              children: [
                const Text('共享播放控件', key: ValueKey('transport')),
                Expanded(
                  child: PlayerContentTransition(
                    direction: direction,
                    child: Center(
                      key: ValueKey(recording),
                      child: Text('歌曲 $recording'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
      final transport = tester.element(find.byKey(const ValueKey('transport')));
      update(() {
        recording = 'B';
        direction = 1;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final right = tester.getCenter(find.text('歌曲 B')).dx;
      expect(right, greaterThan(160));
      await capture(tester, 'transition-next-middle');
      await tester.pump(const Duration(milliseconds: 450));
      update(() {
        recording = 'A';
        direction = -1;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(tester.getCenter(find.text('歌曲 A')).dx, lessThan(160));
      expect(
        identical(
          transport,
          tester.element(find.byKey(const ValueKey('transport'))),
        ),
        true,
      );
      await capture(tester, 'transition-previous-middle');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
