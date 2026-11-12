import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:mesting_music/features/music_platform/netease/together/together_cumulative.dart';
import 'netease_v114_workflows_test.dart' show FakeTogetherPlayer, eapiBody;
import 'support/release_133_qa.dart' show initialize133QA, theme133;

// This large synthetic snapshot exercises the user's reported magnitude. It is
// never an observation of their account or a constant in application code.
const historySeconds = 15788 * 3600 + 53 * 60;

class _Clock extends Fake implements Stopwatch {
  Duration time = Duration.zero;
  bool running = false;
  @override
  Duration get elapsed => time;
  @override
  void start() => running = true;
  @override
  void stop() => running = false;
  @override
  void reset() => time = Duration.zero;
  void advance(Duration duration) {
    if (running) time += duration;
  }
}

class _Room {
  _Room({String account = '7'}) {
    api =
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
                      'user': {'userId': account, 'nickname': '我'},
                    },
                    {
                      'user': {'userId': 8, 'nickname': '好友'},
                    },
                  ],
                },
              };
            } else if (path.endsWith('/relation/statistics/get/v2')) {
              // Assert captured wire values after restore, outside the controller's
              // recoverable-network catch, so a failed assertion cannot be swallowed.
              queries.add(eapiBody(request));
              data = statistics;
            } else if (path.endsWith('/end/v2')) {
              exits++;
            }
            return http.Response(
              jsonEncode({'code': 200, 'data': data}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        )..configure(
          NeteaseSession(
            userId: account,
            cookies: const {'MUSIC_U': 'fixture-only'},
            deviceId: 'fixture-only',
          ),
        );
    music = NeteaseMusicRepository(api);
    controller = createController();
  }
  final player = FakeTogetherPlayer();
  final queries = <Map<String, dynamic>>[];
  final clock = _Clock();
  String room = 'room-a';
  int exits = 0;
  Map<String, Object?> statistics = {
    'totalConnectionTime': historySeconds,
    'currentConnectionTime': 60,
  };
  late final NeteaseApi api;
  late final NeteaseMusicRepository music;
  late NeteaseTogetherController controller;
  NeteaseTogetherController createController() => NeteaseTogetherController(
    music: music,
    player: player,
    messages: NeteaseMessagesRepository(music),
    isCurrent: () => true,
    automaticTimer: false,
    cumulativeClock: TogetherCumulativeClock(clock: clock),
  );
  Future<void> close() async {
    controller.dispose();
    await player.close();
  }
}

void main() {
  setUpAll(initialize133QA);
  test(
    'official v2 wire query carries numeric friend and self, and current room',
    () async {
      final room = _Room();
      addTearDown(room.close);
      await room.controller.restore();
      expect(room.queries.single['roomUserIds'], '[8,7]');
      expect(room.queries.single['roomId'], 'room-a');
      expect(room.controller.togetherDuration!.inSeconds, historySeconds);
      expect(room.controller.togetherDurationLabel, '一起听了 15788 小时 53 分钟');
    },
  );
  test(
    'missing account identity never sends a one-user relation query',
    () async {
      final room = _Room(account: '');
      addTearDown(room.close);
      await room.controller.restore();
      expect(room.queries, isEmpty);
      expect(room.controller.togetherDuration, isNull);
    },
  );
  test(
    'resume replaces history including background time, independent of playback',
    () async {
      final room = _Room();
      addTearDown(room.close);
      await room.controller.restore();
      room.player.playing = false;
      room.clock.advance(const Duration(minutes: 12));
      expect(room.controller.togetherDuration!.inSeconds, historySeconds + 720);
      // The server already includes the interval. Do not add the old elapsed
      // time or currentConnectionTime again when accepting the new snapshot.
      room.statistics = {
        'totalConnectionTime': historySeconds + 720,
        'currentConnectionTime': 780,
      };
      await room.controller.resume();
      expect(room.queries, hasLength(2));
      expect(room.controller.togetherDuration!.inSeconds, historySeconds + 720);
      await room.controller.tick();
      expect(
        room.queries,
        hasLength(2),
        reason: 'Normal polling remains throttled.',
      );
      expect(room.exits, 0);
    },
  );
  test(
    'process recreation restores server history without a local elapsed counter',
    () async {
      final room = _Room();
      addTearDown(room.close);
      await room.controller.restore();
      room.controller.dispose();
      room.statistics = {
        'totalConnectionTime': historySeconds + 3600,
        'currentConnectionTime': 3660,
      };
      room.controller = room.createController();
      expect(room.controller.togetherDuration, isNull);
      await room.controller.restore();
      expect(
        room.controller.togetherDuration!.inSeconds,
        historySeconds + 3600,
      );
      expect(
        room.exits,
        0,
        reason: 'Controller disposal must not leave the official room.',
      );
    },
  );
  test(
    'same-room zero preserves confirmed total; different room starts independently',
    () async {
      final room = _Room();
      addTearDown(room.close);
      await room.controller.restore();
      room.clock.advance(const Duration(seconds: 35));
      room.statistics = {'totalConnectionTime': 0, 'currentConnectionTime': 0};
      await room.controller.restore();
      expect(room.controller.togetherDuration!.inSeconds, historySeconds + 35);
      expect(room.controller.togetherDurationIsStale, isTrue);
      room.clock.advance(const Duration(hours: 1));
      expect(room.controller.togetherDuration!.inSeconds, historySeconds + 35);
      room.room = 'room-b';
      await room.controller.restore();
      expect(room.controller.togetherDuration, Duration.zero);
      expect(room.controller.togetherDurationIsStale, isFalse);
    },
  );
  test(
    'clock accepts new snapshots by replacement and freezes only when stale',
    () {
      final clock = _Clock();
      final total = TogetherCumulativeClock(clock: clock);
      expect(total.duration, isNull);
      total.replace(const Duration(seconds: 100));
      clock.advance(const Duration(seconds: 90));
      expect(total.duration, const Duration(seconds: 190));
      total.replace(const Duration(seconds: 190));
      expect(total.duration, const Duration(seconds: 190));
      clock.advance(const Duration(seconds: 10));
      total.markStale();
      clock.advance(const Duration(days: 1));
      expect(total.duration, const Duration(seconds: 200));
      expect(total.isStale, isTrue);
      total.replace(const Duration(seconds: 86400));
      expect(total.duration, const Duration(days: 1));
      expect(total.isStale, isFalse);
      total.clear();
      expect(total.duration, isNull);
      expect(clock.running, isFalse);
    },
  );
  for (final pair in [
    ('', '8'),
    ('7', ''),
    ('7', '7'),
    ('-7', '8'),
    ('7', 'bad'),
  ]) {
    test('incomplete/invalid relation $pair is not queryable', () {
      expect(togetherRelationUserIds(pair.$1, pair.$2), isNull);
    });
  }
  testWidgets('long official cumulative label fits a narrow player header', (
    tester,
  ) async {
    final room = _Room();
    addTearDown(room.close);
    await room.controller.restore();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 420);
    addTearDown(tester.view.reset);
    const key = ValueKey('history134-capture');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          neteaseTogetherControllerProvider.overrideWithValue(room.controller),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme133(true),
            home: const Scaffold(
              body: Center(
                child: NeteaseTogetherPlayerHeader(onManage: _manage),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('一起听了 15788 小时 53 分钟'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_134')) {
      final future = tester
          .renderObject<RenderRepaintBoundary>(find.byKey(key))
          .toImage();
      await tester.runAsync(() async {
        final image = await future;
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          '.codex-artifacts/2026-11-01-release134/ui/long-cumulative.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
  });
}

void _manage() {}
