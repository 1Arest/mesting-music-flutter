import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/domain/platform_regions.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_region_picker.dart';
import 'support/release_133_qa.dart';

void main() {
  setUpAll(initialize133QA);
  test(
    'code boundaries resolve names, short codes, district codes and direct cities',
    () async {
      final regions = await loadMusicRegions();
      for (final value in ['44', '440000', '广东省']) {
        final result = resolveMusicRegion(
          regions,
          province: value,
          city: '440305',
        );
        expect(result.province!.name, '广东省');
        expect(result.city!.name, '深圳市');
      }
      expect(
        resolveMusicRegion(
          regions,
          province: '410000',
          city: '419001',
        ).city!.name,
        '济源市',
      );
      expect(
        resolveMusicRegion(
          regions,
          province: '110000',
          city: '110100',
        ).city!.name,
        '北京市',
      );
      expect(
        resolveMusicRegion(
          regions,
          province: '999999',
          city: '999999',
        ).province,
        isNull,
      );
      expect(musicRegionMatches('广东省', '44', '440'), isFalse);
    },
  );
  for (final selected in [false, true]) {
    testWidgets(
      'region picker keeps national order and resolves six digit selection selected=$selected',
      (tester) async {
        final regions = (await tester.runAsync(loadMusicRegions))!;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        ({String province, String city})? result;
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture133Key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme133(selected),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () async {
                        result = await showPlatformRegionPicker(
                          context,
                          regions,
                          province: selected ? '440000' : null,
                          city: selected ? '440300' : null,
                        );
                      },
                      child: const Text('地区'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('地区'));
        await tester.pumpAndSettle();
        final pickers = tester
            .widgetList<CupertinoPicker>(find.byType(CupertinoPicker))
            .toList();
        expect(find.text('440000'), findsNothing);
        expect(find.text('440300'), findsNothing);
        final first =
            (pickers[0].childDelegate as ListWheelChildListDelegate)
                    .children
                    .first
                as Center;
        expect((first.child as Text).data, '北京市');
        expect(
          pickers[0].scrollController!.selectedItem,
          selected ? regions.indexWhere((r) => r.name == '广东省') : 0,
        );
        if (selected) {
          expect(
            pickers[1].scrollController!.selectedItem,
            regions
                .firstWhere((r) => r.name == '广东省')
                .cities
                .indexWhere((c) => c.name == '深圳市'),
          );
        }
        await capture133UI(tester, 'region-selected-$selected');
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
        expect(
          result,
          selected
              ? (province: '广东省', city: '深圳市')
              : (province: '北京市', city: '北京市'),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final legacy in [false, true]) {
    testWidgets(
      'unknown numeric values never become options; cancel preserves draft legacy=$legacy',
      (tester) async {
        final regions = (await tester.runAsync(loadMusicRegions))!;
        var completed = false;
        ({String province, String city})? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme133(false),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showPlatformRegionPicker(
                      context,
                      regions,
                      province: legacy ? '旧地区' : '999999',
                      city: legacy ? '原城市' : '999900',
                    );
                    completed = true;
                  },
                  child: const Text('地区'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('地区'));
        await tester.pumpAndSettle();
        final picker = tester.widget<CupertinoPicker>(
          find.byType(CupertinoPicker).first,
        );
        final children =
            (picker.childDelegate as ListWheelChildListDelegate).children;
        expect(((children.first as Center).child as Text).data, '北京市');
        expect(
          picker.scrollController!.selectedItem,
          legacy ? regions.length : 0,
        );
        expect(find.text('999999'), findsNothing);
        expect(find.text('999900'), findsNothing);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(completed, isTrue);
        expect(result, isNull);
      },
    );
  }
}
