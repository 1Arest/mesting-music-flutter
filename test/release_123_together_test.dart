import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:mesting_music/features/music_platform/netease/together/netease_together_exit.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_presence.dart';
import 'netease_v114_workflows_test.dart' show FakeTogetherPlayer, eapiBody;

class _Location extends TogetherLocationGateway {
  _Location(this.result);
  Future<TogetherLocationFix> Function() result;
  int requests = 0;
  @override
  Future<TogetherLocationFix> requestFix() {
    requests++;
    return result();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NeteaseTogetherController controller;
  late FakeTogetherPlayer player;
  late _Location location;
  late List<Map<String, dynamic>> gps;
  late bool current, inRoom, gpsAccepted;
  late bool exitAccepted;
  late int exitRequests;
  bool failExitTransport = false;
  Completer<http.Response>? pendingStatus;
  Completer<http.Response>? pendingCommand;
  setUp(() {
    current = inRoom = true;
    gpsAccepted = true;
    exitAccepted = true;
    exitRequests = 0;
    failExitTransport = false;
    pendingStatus = null;
    pendingCommand = null;
    gps = [];
    location = _Location(() async => const TogetherLocationFix(30, 120, 500));
    player = FakeTogetherPlayer();
    final api =
        NeteaseApi(
          MockClient((request) async {
            final path = request.url.path;
            if (path.endsWith('/play/command/report') &&
                pendingCommand != null) {
              return pendingCommand!.future;
            }
            var data = <String, Object?>{};
            if (path.endsWith('/status/get')) {
              if (pendingStatus != null) return pendingStatus!.future;
              data = {
                'inRoom': inRoom,
                'roomInfo': {
                  'roomId': 'room-1',
                  'roomUsers': [
                    {
                      'user': {'userId': 7, 'nickname': '我'},
                    },
                    {
                      'user': {'userId': 8, 'nickname': '音乐朋友'},
                    },
                  ],
                },
              };
            } else if (path.endsWith('/user/gps/report')) {
              gps.add(eapiBody(request));
              data = {'success': gpsAccepted};
            } else if (path.endsWith('/distance/get')) {
              data = {'distance': 12.34, 'unopenedUserIds': []};
            } else if (path.endsWith('/relation/statistics/get/v2')) {
              expect(eapiBody(request)['roomUserIds'], '[8,7]');
              data = {
                'totalConnectionTime': 7260,
                'currentConnectionTime': 120,
              };
            } else if (path.endsWith('/end/v2')) {
              exitRequests++;
              if (failExitTransport) {
                throw http.ClientException('synthetic offline');
              }
              data = {'success': exitAccepted};
              if (exitAccepted) inRoom = false;
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
            cookies: {'MUSIC_U': 'fixture'},
            deviceId: 'fixture',
          ),
        );
    final music = NeteaseMusicRepository(api);
    controller = NeteaseTogetherController(
      music: music,
      player: player,
      messages: NeteaseMessagesRepository(music),
      isCurrent: () => current,
      automaticTimer: false,
      locationGateway: location,
    );
  });
  tearDown(() async {
    controller.dispose();
    await player.close();
  });

  test(
    'restore obtains official seconds and never asks for GPS implicitly',
    () async {
      await controller.restore();
      expect(controller.peers.single.id, '8');
      expect(
        controller.togetherDuration!.inSeconds,
        inInclusiveRange(7260, 7261),
      );
      expect(location.requests, 0);
      expect(gps, isEmpty);
      await controller.restore();
      expect(controller.togetherDuration!.inHours, 2);
    },
  );
  test(
    'exit keeps local song, queue, position and playing state intact',
    () async {
      await controller.restore();
      final track = player.track,
          queue = player.tracks,
          position = player.position;
      final applications = player.applications;
      await controller.end();
      expect(exitRequests, 1);
      expect(controller.active, isFalse);
      expect(controller.sharedTracks, isEmpty);
      expect(controller.members, isEmpty);
      expect(player.track, same(track));
      expect(player.tracks, same(queue));
      expect(player.position, position);
      expect(player.playing, isTrue);
      player.commandController.add('pause');
      await controller.settle();
      await controller.tick();
      expect(player.applications, applications);
      expect(exitRequests, 1);
    },
  );
  test(
    'a rejected exit keeps the room and allows one explicit retry',
    () async {
      await controller.restore();
      exitAccepted = false;
      await controller.end();
      expect(controller.active, isTrue);
      expect(controller.error, contains('未确认退出'));
      expect(controller.ending, isFalse);
      expect(player.playing, isTrue);
      expect(exitRequests, 1);
      exitAccepted = true;
      await controller.end();
      expect(controller.active, isFalse);
      expect(controller.error, isNull);
      expect(exitRequests, 2);
    },
  );
  test('an old status response cannot restore a room after exit', () async {
    await controller.restore();
    pendingStatus = Completer<http.Response>();
    final tick = controller.tick();
    await Future<void>.delayed(Duration.zero);
    await controller.end();
    pendingStatus!.complete(
      http.Response(
        jsonEncode({
          'code': 200,
          'data': {
            'inRoom': true,
            'roomInfo': {'roomId': 'room-1'},
            'commandInfo': {
              'serverSeq': 42,
              'songId': '17',
              'userId': 8,
              'playStatus': 'PAUSE',
              'progress': 0,
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await tick;
    expect(controller.active, isFalse);
    expect(player.playing, isTrue);
    expect(player.applications, 0);
  });
  test(
    'unknown exit result keeps room state without automatically replaying',
    () async {
      await controller.restore();
      failExitTransport = true;
      await controller.end();
      expect(exitRequests, 1);
      expect(controller.active, isTrue);
      expect(controller.error, isNotNull);
      expect(player.playing, isTrue);
      expect(controller.ending, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(exitRequests, 1);
    },
  );
  test('late command errors cannot overwrite a successful exit', () async {
    await controller.restore();
    pendingCommand = Completer<http.Response>();
    player.commandController.add('pause');
    await Future<void>.delayed(Duration.zero);
    await controller.end();
    pendingCommand!.completeError(http.ClientException('late synthetic error'));
    await controller.settle();
    expect(controller.active, isFalse);
    expect(controller.error, isNull);
    expect(player.playing, isTrue);
  });
  test('late poll errors are ignored after a successful exit', () async {
    await controller.restore();
    pendingStatus = Completer<http.Response>();
    final tick = controller.tick();
    await Future<void>.delayed(Duration.zero);
    await controller.end();
    pendingStatus!.completeError(http.ClientException('late synthetic error'));
    await tick;
    expect(controller.active, isFalse);
    expect(controller.error, isNull);
  });
  testWidgets('exit confirmation cancels without a request, then exits once', (
    tester,
  ) async {
    await controller.restore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => confirmNeteaseTogetherExit(context, controller),
              child: const Text('请求退出'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('请求退出'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(exitRequests, 0);
    expect(controller.active, isTrue);
    await tester.tap(find.text('请求退出'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('退出一起听'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(exitRequests, 1);
    expect(controller.active, isFalse);
    expect(player.playing, isTrue);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'explicit location uses the official report and distance routes without Wi-Fi data',
    () async {
      await controller.restore();
      await controller.enableLocation();
      expect(controller.locationEnabled, isTrue);
      expect(controller.distance.kilometres, 12.34);
      expect(gps.single['opened'], 'true');
      expect(gps.single['privacy'], 'true');
      expect(gps.single['latitude'], 30);
      expect(gps.single.containsKey('ssid'), isFalse);
      await controller.disableLocation();
      expect(gps.last['opened'], 'false');
      expect(controller.locationEnabled, isFalse);
      expect(controller.distance.kilometres, isNull);
    },
  );
  test(
    'explicit platform rejection never reports location sharing as enabled or closed',
    () async {
      await controller.restore();
      gpsAccepted = false;
      await controller.enableLocation();
      expect(controller.locationEnabled, isFalse);
      gpsAccepted = true;
      await controller.enableLocation();
      expect(controller.locationEnabled, isTrue);
      gpsAccepted = false;
      await controller.disableLocation();
      expect(controller.locationEnabled, isTrue);
      expect(controller.presenceNotice, contains('未获确认'));
    },
  );
  test('closing the room rejects a late OS location result', () async {
    final pending = Completer<TogetherLocationFix>();
    location.result = () => pending.future;
    await controller.restore();
    final action = controller.enableLocation();
    await controller.end();
    pending.complete(const TogetherLocationFix(30, 120, 40));
    await action;
    expect(gps, isEmpty);
    expect(controller.active, isFalse);
    expect(controller.togetherDuration, isNull);
  });
  test(
    'a changed account never reports coordinates from a pending fix',
    () async {
      final pending = Completer<TogetherLocationFix>();
      location.result = () => pending.future;
      await controller.restore();
      final action = controller.enableLocation();
      current = false;
      pending.complete(const TogetherLocationFix(30, 120, 40));
      await action;
      expect(gps, isEmpty);
    },
  );
  test(
    'denied permission leaves playback synchronization and the room intact',
    () async {
      location.result = () async => throw PlatformException(
        code: 'permission_denied',
        message: '位置权限未开启',
      );
      await controller.restore();
      await controller.enableLocation();
      expect(controller.active, isTrue);
      expect(controller.error, isNull);
      expect(controller.presenceNotice, '位置权限未开启');
      expect(gps, isEmpty);
    },
  );
  test(
    'distance sentinels and invalid fixes cannot become fabricated proximity',
    () {
      for (final value in [0, -1, 'NaN', 999999]) {
        expect(TogetherDistance.parse({'distance': value}).kilometres, isNull);
      }
      expect(
        TogetherDistance.parse({
          'data': {'distance': 10.5},
        }).label,
        contains('10.50'),
      );
      final sharingClosed = TogetherDistance.parse({
        'distance': 12.34,
        'unopenedUserIds': [8],
      });
      expect(sharingClosed.kilometres, isNull);
      expect(sharingClosed.label, '等待对方开启位置');
      expect(
        () => TogetherLocationFix.parse({
          'latitude': 100,
          'longitude': 10,
          'accuracyMeters': 10,
        }),
        throwsFormatException,
      );
      expect(
        formatTogetherDuration(const Duration(minutes: 61)),
        '一起听了 1 小时 1 分钟',
      );
    },
  );
  testWidgets(
    'player room island uses real membership and explicit location consent',
    (tester) async {
      await controller.restore();
      var manages = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            neteaseTogetherControllerProvider.overrideWithValue(controller),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: NeteaseTogetherPlayerHeader(onManage: () => manages++),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('一起听了 2 小时 1 分钟'), findsOneWidget);
      await tester.tap(find.text('开启位置查看距离'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(location.requests, 0);
      expect(find.text('开启位置'), findsOneWidget);
      await tester.tap(find.text('暂不开启'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(gps, isEmpty);
      await tester.tap(find.bySemanticsLabel('与音乐朋友一起听，管理房间'));
      expect(manages, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
