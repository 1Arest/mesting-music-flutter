import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/together/netease_together_controller.dart';
import 'package:mesting_music/features/music_platform/netease/together/netease_together_player_header.dart';
import 'netease_v114_workflows_test.dart' show FakeTogetherPlayer, eapiBody;
import 'support/release_133_qa.dart';

void main() {
  setUpAll(initialize133QA);
  late NeteaseTogetherController controller;
  late FakeTogetherPlayer player;
  late Map<String, Object?> statistics;
  late String peer, room;
  late bool current, failStatistics;
  late int requests;
  Completer<http.Response>? pending;
  setUp(() {
    peer = '8';
    room = 'room-a';
    current = true;
    failStatistics = false;
    requests = 0;
    pending = null;
    statistics = {'totalConnectionTime': 90060, 'currentConnectionTime': 120};
    player = FakeTogetherPlayer();
    final api =
        NeteaseApi(
          MockClient((request) async {
            final path = request.url.path;
            var data = <String, Object?>{};
            if (path.endsWith('/status/get')) {
              data = {
                'inRoom': true,
                'roomInfo': {
                  'roomId': room,
                  'roomUsers': [
                    {
                      'user': {'userId': 7, 'nickname': '我'},
                    },
                    if (peer.isNotEmpty)
                      {
                        'user': {
                          'userId': int.parse(peer),
                          'nickname': '好友 $peer',
                        },
                      },
                  ],
                },
              };
            } else if (path.endsWith('/relation/statistics/get/v2')) {
              requests++;
              expect(eapiBody(request)['roomUserIds'], '[$peer,7]');
              if (pending != null) return pending!.future;
              if (failStatistics) {
                throw http.ClientException('synthetic offline');
              }
              data = statistics;
            }
            return http.Response(
              jsonEncode({'code': 200, 'data': data}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        )..configure(
          const NeteaseSession(
            userId: '7',
            cookies: {'MUSIC_U': 'fixture-only'},
            deviceId: 'fixture-only',
          ),
        );
    final music = NeteaseMusicRepository(api);
    controller = NeteaseTogetherController(
      music: music,
      player: player,
      messages: NeteaseMessagesRepository(music),
      isCurrent: () => current,
      automaticTimer: false,
    );
  });
  tearDown(() async {
    controller.dispose();
    await player.close();
  });

  test(
    'current session alone never masquerades as official friend cumulative time',
    () async {
      statistics = {'currentConnectionTime': 120};
      await controller.restore();
      expect(controller.togetherDuration, isNull);
    },
  );
  test(
    'official total replaces rather than adds a session or a repeated snapshot',
    () async {
      await controller.restore();
      expect(
        controller.togetherDuration!.inSeconds,
        inInclusiveRange(90060, 90061),
      );
      await controller.restore();
      expect(
        controller.togetherDuration!.inSeconds,
        inInclusiveRange(90060, 90061),
      );
      statistics = {'totalConnectionTime': 90120, 'currentConnectionTime': 180};
      await controller.restore();
      expect(
        requests,
        3,
        reason: 'Explicit refresh bypasses the polling throttle.',
      );
      expect(
        controller.togetherDuration!.inSeconds,
        inInclusiveRange(90120, 90121),
      );
    },
  );
  test(
    'failed totals retain only this friend last confirmed snapshot as stale',
    () async {
      await controller.restore();
      failStatistics = true;
      await controller.restore();
      expect(controller.togetherDurationIsStale, isTrue);
      expect(controller.togetherDurationLabel, contains('上次同步'));
      failStatistics = false;
      statistics = {'totalConnectionTime': 0, 'currentConnectionTime': 0};
      await controller.restore();
      expect(controller.togetherDurationIsStale, isTrue);
      expect(
        controller.togetherDuration!.inSeconds,
        inInclusiveRange(90060, 90061),
      );
    },
  );
  test(
    'all friend identities use their own official history; leaving clears it',
    () async {
      await controller.restore();
      peer = '9';
      statistics = {'totalConnectionTime': 367200, 'currentConnectionTime': 30};
      await controller.restore();
      expect(controller.togetherDuration!.inHours, 102);
      peer = '10';
      statistics = {'currentConnectionTime': 60};
      await controller.restore();
      expect(controller.togetherDuration, isNull);
      peer = '';
      await controller.restore();
      expect(controller.togetherDuration, isNull);
    },
  );
  test(
    'new room and account cannot inherit a delayed official total',
    () async {
      await controller.restore();
      room = 'room-b';
      statistics = {'currentConnectionTime': 30};
      await controller.restore();
      expect(controller.togetherDuration, isNull);
      pending = Completer<http.Response>();
      final restoring = controller.restore();
      for (var i = 0; i < 30 && requests < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      current = false;
      pending!.complete(
        http.Response(
          jsonEncode({
            'code': 200,
            'data': {'totalConnectionTime': 999000},
          }),
          200,
        ),
      );
      await restoring;
      expect(controller.togetherDuration, isNull);
    },
  );
  for (final total in [-1, 'bad', 999999999999, 1.5, true]) {
    test(
      'invalid cumulative $total never falls back to session time',
      () async {
        statistics = {
          'totalConnectionTime': total,
          'currentConnectionTime': 120,
        };
        await controller.restore();
        expect(controller.togetherDuration, isNull);
      },
    );
  }
  for (final available in [false, true]) {
    testWidgets(
      'player header distinguishes missing and official cumulative available=$available',
      (tester) async {
        if (!available) statistics = {'currentConnectionTime': 120};
        await controller.restore();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 500);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              neteaseTogetherControllerProvider.overrideWithValue(controller),
            ],
            child: RepaintBoundary(
              key: capture133Key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme133(true),
                home: Scaffold(
                  body: Center(
                    child: NeteaseTogetherPlayerHeader(onManage: () {}),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.text(available ? '一起听了 25 小时 1 分钟' : '累计时长暂未获取'),
          findsOneWidget,
        );
        await capture133UI(tester, 'together-official-total-$available');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
