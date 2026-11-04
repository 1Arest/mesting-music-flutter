import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_message_card.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_message_card_view.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_record.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_records_repository.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_records_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'release_141_type51_message_test.dart' show type51Fixture;

// Fixtures follow observed official JS field contracts, never a captured
// account. The legacy card uses the shipped CommonMessage.fromJson schema.
const _self = NeteaseTogetherProfile(id: '7', name: '合成测试本人');
const _peer = NeteaseTogetherProfile(id: '8', name: '合成测试好友');
const _record = NeteaseTogetherRecord(
  id: 'first',
  roomId: 'fixture_room_1',
  self: _self,
  peer: _peer,
  duration: Duration(hours: 26, minutes: 5),
  songCount: 224,
  totalDuration: Duration(hours: 15808, minutes: 16),
  totalSongCount: 18344,
  distanceKilometres: 3167.77,
  canInvite: true,
  online: false,
  showCollectButton: true,
);

class _Records extends NeteaseTogetherRecordsRepository {
  _Records()
    : super(
        NeteaseMusicRepository(
          NeteaseApi(
            MockClient((_) async => throw StateError('Unexpected network')),
          ),
        ),
      );
  bool current = true, fail = false, limited = false;
  Completer<NeteaseTogetherRecord>? pending;
  final calls = <String>[];
  @override
  void checkOwner() {
    if (!current) throw StateError('Account changed');
  }

  @override
  Future<NeteaseTogetherRecord> report(String roomId, {String? peerId}) async {
    calls.add('report:$roomId');
    if (fail) throw StateError('合成网络失败');
    return pending?.future ?? _record;
  }

  @override
  Future<NeteaseTogetherHistoryPageData> history({String? cursor}) async {
    calls.add('history:${cursor ?? ''}');
    return NeteaseTogetherHistoryPageData(
      records: cursor == null
          ? [
              _record,
              const NeteaseTogetherRecord(
                id: 'hidden',
                roomId: 'fixture_hidden',
                peer: _peer,
                duration: Duration(minutes: 3),
                songCount: 2,
              ),
            ]
          : [
              const NeteaseTogetherRecord(
                id: 'second',
                roomId: 'fixture_room_2',
                peer: _peer,
                duration: Duration(minutes: 18),
                songCount: 5,
              ),
            ],
      mostListened: _record,
      vip: !limited,
      hasMore: cursor == null,
      nextCursor: cursor == null ? 'next' : null,
    );
  }
}

const _capture = bool.fromEnvironment('CAPTURE_V140');
const _captureKey = ValueKey('v140-capture');

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (_capture) {
      for (final family in [
        'V140QA',
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'sans-serif',
      ]) {
        await (FontLoader(family)..addFont(
              File(
                'C:/Windows/Fonts/msyh.ttc',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
      await (FontLoader('MaterialIcons')..addFont(
            File(
              'D:/CodexCache/flutter-3.41.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    }
  });

  Future<void> mount(
    WidgetTester tester,
    Widget page,
    _Records repository, {
    bool dark = false,
    bool compact = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    tester.view.physicalSize = compact
        ? const Size(320, 700)
        : const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    if (_capture) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'V140QA'),
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          neteaseTogetherRecordsRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
        child: MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(compact ? 1.4 : 1)),
            child: RepaintBoundary(key: _captureKey, child: child!),
          ),
          home: page,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!_capture) return;
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(_captureKey))
          .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      const captureDir = String.fromEnvironment(
        'RECORDS_CAPTURE_DIR',
        defaultValue: '.codex-artifacts/2026-11-02-v140-fixes/ui',
      );
      final target = File('$captureDir/$name.png');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  test(
    'official mp ending generalMsg keeps room, duration and strict host boundary',
    () {
      final message = NeteaseChatMessage.parse({
        'msg': jsonEncode({
          'type': 23,
          'generalMsg': {
            'title': '我们一起听了',
            'subTitle': '26小时5分钟',
            'nativeUrl':
                'orpheus://nm/webview?url=${Uri.encodeComponent('https://mp.music.163.com/5fbcd6a217aef81f3a03eda5/ending/index.html?roomId=fixture_room_1')}',
          },
        }),
      });
      expect(message.card?.togetherRoomId, 'fixture_room_1');
      expect(message.card?.duration, const Duration(hours: 26, minutes: 5));
      expect(message.card?.togetherRecord, isTrue);
      expect(
        NeteaseMessageCard.officialUrl(
          'https://mp.music.163.com.evil.test/ending',
        ),
        isNull,
      );
      expect(
        NeteaseMessageCard.parse({
          'generalMsg': {'title': '一起听记录', 'totalConnectionTime': 999999},
        })?.duration,
        isNull,
        reason: 'A relation total cannot impersonate this session.',
      );
      expect(
        NeteaseChatMessage.parse({
          'msg': jsonEncode({'type': 23}),
        }).diagnostics,
        isNotNull,
      );
    },
  );

  testWidgets(
    'ended card opens actual report then all records without writes',
    (tester) async {
      final repository = _Records();
      final payload = type51Fixture(time: '26小时5分钟');
      final body = payload['opaqueRecordContainer'] as Map;
      body['creatorAvatarUrl'] = '';
      body['acceptorAvatarUrl'] = '';
      final parsed = NeteaseChatMessage.parse({
        'msg': jsonEncode(payload),
      }).card!;
      await mount(
        tester,
        Scaffold(
          body: SafeArea(
            // A chat bubble is a 300dp-wide child of an unbounded vertical
            // list. Mount it with that contract, not tight full-screen bounds.
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 300,
                    child: NeteaseMessageCardView(
                      card: parsed,
                      time: DateTime(2026, 11, 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        repository,
      );
      expect(find.text('26小时5分钟 ›'), findsOneWidget);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('netease-together-message-card')),
            )
            .height,
        lessThan(150),
      );
      await capture(tester, 'chat-ended-record');
      await tester.tap(
        find.byKey(const ValueKey('netease-message-card-detail')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('together-record-page')),
        findsOneWidget,
      );
      expect(find.text('26小时5分钟'), findsOneWidget);
      expect(find.text('224首歌曲'), findsOneWidget);
      expect(find.textContaining('15808小时16分钟'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('together-all-records')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('together-history-page')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('together-history-more')),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('together-history-more')));
      await tester.pumpAndSettle();
      expect(repository.calls, [
        'report:synthetic_room',
        'history:',
        'history:next',
      ]);
      expect(
        find.byKey(const ValueKey('together-history-record-second')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    for (final compact in [false, true]) {
      testWidgets('report and history readable dark=$dark compact=$compact', (
        tester,
      ) async {
        final repository = _Records();
        await mount(
          tester,
          const NeteaseTogetherRecordPage(
            roomId: 'fixture_room_1',
            peer: _peer,
          ),
          repository,
          dark: dark,
          compact: compact,
        );
        expect(find.text('和TA的一起听'), findsOneWidget);
        await capture(
          tester,
          'report-${dark ? 'dark' : 'light'}-${compact ? 'large-text' : 'phone'}',
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('together-all-records')));
        await tester.pumpAndSettle();
        await capture(
          tester,
          'history-${dark ? 'dark' : 'light'}-${compact ? 'large-text' : 'phone'}',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'membership restricted rows are never detail links or local totals',
    (tester) async {
      final repository = _Records()..limited = true;
      await mount(tester, const NeteaseTogetherHistoryPage(), repository);
      expect(
        find.byKey(const ValueKey('together-history-record-hidden')),
        findsNothing,
      );
      expect(find.textContaining('15808小时16分钟'), findsNothing);
      expect(find.byKey(const ValueKey('together-history-more')), findsNothing);
      expect(
        find.byKey(const ValueKey('together-history-membership-limit')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'report failure retries and late account changes hide statistics',
    (tester) async {
      final repository = _Records()..fail = true;
      await mount(
        tester,
        const NeteaseTogetherRecordPage(roomId: 'fixture_room_1'),
        repository,
      );
      expect(find.textContaining('合成网络失败'), findsOneWidget);
      repository.fail = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('224首歌曲'), findsOneWidget);
      repository.current = false;
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            neteaseTogetherRecordsRepositoryProvider.overrideWithValue(
              repository,
            ),
          ],
          child: const MaterialApp(
            home: NeteaseTogetherRecordPage(roomId: 'fixture_room_1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('账号已变化'), findsOneWidget);
      expect(find.text('224首歌曲'), findsNothing);
    },
  );
}
