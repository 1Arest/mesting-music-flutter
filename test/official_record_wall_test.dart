import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_record_wall.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_report_extras.dart';
import 'support/personal_profile_fixture.dart';

void main() {
  test('官方封面墙短列表补齐，完整墙按四列保留顺序', () {
    final entries = List.generate(22, (i) => 'cover-$i');
    final full = officialRecordWallColumns(entries);
    expect(full[1], ['cover-1', 'cover-5', 'cover-9', 'cover-13', 'cover-17']);
    expect(full.expand((column) => column).length, 20);
    for (final count in [1, 2, 4, 5, 10]) {
      final short = officialRecordWallColumns(entries.take(count).toList());
      expect(short.map((column) => column.length), [6, 6, 6, 6]);
      expect(
        short.expand((column) => column).toSet(),
        entries.take(count).toSet(),
      );
    }
  });

  testWidgets('唱片墙仅在可见且允许动画时推进，导出画面静止', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    Widget page({required bool animate}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          controller: scroll,
          child: Column(
            children: [
              SizedBox(
                width: 300,
                child: OfficialRecordWall(
                  data: const OfficialReportExtras(
                    covers: [profileFixtureCover],
                    songCount: 1,
                  ),
                  period: '2026-11-01 – 2026-11-07',
                  animate: animate,
                ),
              ),
              const SizedBox(height: 1000),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(page(animate: true));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    Animation<dynamic> motion() =>
        tester
                .widget<AnimatedBuilder>(
                  find
                      .descendant(
                        of: find.byType(OfficialRecordWall),
                        matching: find.byType(AnimatedBuilder),
                      )
                      .first,
                )
                .animation
            as Animation<dynamic>;
    expect(motion().value, greaterThan(0));
    scroll.jumpTo(480);
    await tester.pump();
    final value = motion().value;
    await tester.pump(const Duration(seconds: 1));
    expect(motion().value, value);
    scroll.jumpTo(0);
    await tester.pumpWidget(page(animate: false));
    await tester.pump();
    final fixed = motion().value;
    await tester.pump(const Duration(seconds: 1));
    expect(motion().value, fixed);
    expect(tester.takeException(), isNull);
  });
}
