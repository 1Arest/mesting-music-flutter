import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mesting_music/core/platform/lyrics_overlay_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop lyrics accepts animated line and color updates', (
    tester,
  ) async {
    final bridge = LyricsOverlayBridge()..startListening();
    addTearDown(bridge.hide);

    expect(
      await bridge.canDrawOverlays(),
      isTrue,
      reason: 'The Android overlay permission must be granted for this test.',
    );
    expect(
      await bridge.show(const {
        'current': '第一句歌词正在播放',
        'next': '第二句歌词准备接替',
        'playing': true,
        'fontSize': 21.0,
        'textColor': '#FFFFFFFF',
        'locked': false,
      }),
      isTrue,
    );

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await bridge.update(const {
      'current': '第二句歌词准备接替',
      'next': '第三句歌词平滑出现',
      'playing': true,
      'fontSize': 21.0,
      'textColor': '#FFFF7FA0',
      'locked': false,
    });
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await bridge.update(const {
      'current': '第三句歌词平滑出现',
      'next': '颜色与动画都已更新',
      'playing': true,
      'fontSize': 21.0,
      'textColor': '#FF70E2FF',
      'locked': false,
    });
    await tester.runAsync(
      () => Future<void>.delayed(
        const Duration(
          seconds: int.fromEnvironment(
            'LYRICS_OVERLAY_HOLD_SECONDS',
            defaultValue: 0,
          ),
          milliseconds: 500,
        ),
      ),
    );
  });
}
