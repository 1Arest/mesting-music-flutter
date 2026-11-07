import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/widgets/music_notice.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/shared/widgets/beta_success_feedback.dart';

void main() {
  testWidgets('播放模式使用自定义悬浮提示并自动淡出', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMusicNotice(
                context,
                icon: Icons.shuffle_rounded,
                title: '随机播放',
                message: '播放模式已切换',
              ),
              child: const Text('切换'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('切换'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('随机播放'), findsOneWidget);
    expect(find.text('播放模式已切换'), findsNothing);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.pump(const Duration(milliseconds: 1950));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('随机播放'), findsNothing);
  });

  testWidgets('纯文字版本状态不显示图标或副文案', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMusicNotice(
                context,
                icon: null,
                title: '已是最新版本',
                message: '',
              ),
              child: const Text('检查更新'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('检查更新'));
    await tester.pump();

    expect(find.text('已是最新版本'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.textContaining('当前 v'), findsNothing);
  });

  testWidgets('已添加使用顶部 Apple 毛玻璃提示并避开底部控件', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            viewPadding: EdgeInsets.only(bottom: 24),
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showMusicNotice(
                  context,
                  icon: Icons.check_rounded,
                  title: '已添加',
                  message: '',
                ),
                child: const Text('添加'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('添加'));
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('已添加'), findsOneWidget);
    expect(find.textContaining('✅'), findsNothing);
    expect(
      tester.widget<Text>(find.text('已添加')).style?.decoration,
      TextDecoration.none,
    );
    final positioned = tester.widget<Positioned>(
      find.ancestor(of: find.text('已添加'), matching: find.byType(Positioned)),
    );
    expect(positioned.top, 12);
    expect(positioned.bottom, isNull);
    if (DistributionChannel.isBeta) {
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(
        tester.widget<BetaSuccessMark>(find.byType(BetaSuccessMark)).animated,
        false,
      );
    } else {
      expect(tester.widget<Icon>(find.byIcon(Icons.check_rounded)).size, 22);
    }
    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
