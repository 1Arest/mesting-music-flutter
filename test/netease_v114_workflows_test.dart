import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_store.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_listening_reporter.dart';
import 'package:mesting_music/features/music_platform/netease/netease_fallback.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/together/netease_together_controller.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_catalog.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_content.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_workflow_policy.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'release_107_listening_sync_test.dart' show FakeClock, FakeFeed;

const session = NeteaseSession(
  userId: '7',
  deviceId: 'fixture',
  cookies: {'MUSIC_U': 'synthetic-v114-only'},
);
const song = Track(
  id: 'netease_17',
  title: '玻璃',
  artist: 'Gareth.T',
  album: '玻璃 demo',
  duration: Duration(minutes: 4),
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.netease,
  platformSongId: '17',
);

/// Inspect the encrypted request at the transport boundary, not a duplicate of
/// a payload builder. The eapi key is a public protocol constant, not a secret.
Map<String, dynamic> eapiBody(http.Request request) {
  final hex = request.bodyFields['params']!;
  final bytes = Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
  final cipher = PaddedBlockCipher('AES/ECB/PKCS7')
    ..init(
      false,
      PaddedBlockCipherParameters(
        KeyParameter(Uint8List.fromList(utf8.encode('e82ckenh8dichen8'))),
        null,
      ),
    );
  final text = utf8.decode(cipher.process(bytes));
  return Map<String, dynamic>.from(
    jsonDecode(text.split('-36cd479b6b5-')[1]) as Map,
  );
}

http.Response response(Map<String, Object?> data) => http.Response(
  jsonEncode({'code': 200, ...data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class FakeTogetherPlayer implements NeteaseTogetherPlayer {
  @override
  Track? track = song;
  @override
  List<Track> tracks = [song];
  @override
  bool playing = true;
  @override
  Duration position = const Duration(seconds: 8);
  final commandController = StreamController<String>.broadcast(sync: true);
  final trackController = StreamController<String>.broadcast(sync: true);
  @override
  Stream<String> get commands => commandController.stream;
  @override
  Stream<String> get trackChanges => trackController.stream;
  int applications = 0;
  @override
  Future<void> apply(
    List<Track> queue,
    String id,
    Duration pos,
    bool play,
  ) async {
    applications++;
    tracks = queue;
    track = queue.firstWhere((t) => t.platformSongId == id);
    position = pos;
    playing = play;
    commandController.add(play ? 'play' : 'pause');
  }

  Future<void> close() async {
    await commandController.close();
    await trackController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'conversation decodes the peer and last message without profile fields',
    () {
      final conversation = NeteaseConversation.parse({
        'id': 4,
        'newMsgCount': 2,
        'lastMsgTime': 1793250000000,
        'lastMsg': jsonEncode({'type': 1, 'msg': '你好 [大笑]'}),
        'fromUser': {
          'userId': 7,
          'nickname': '我',
          'province': 430000,
          'birthday': -2209017600000,
        },
        'toUser': {'userId': 8, 'nickname': '朋友', 'city': 430100},
      }, '7');
      expect(conversation.peer.id, '8');
      expect(conversation.peer.name, '朋友');
      expect(conversation.last.text, '你好 [大笑]');
      expect(conversation.unread, 2);
      final image = NeteaseChatMessage.parse({
        'id': 5,
        'msg': jsonEncode({
          'type': 6,
          'picInfo': {'picUrl': 'https://p1.music.126.net/image.jpg'},
        }),
      });
      expect(image.image, contains('image.jpg'));
      expect(image.text, '[图片]');
    },
  );
  test(
    'private text is one eapi send with a fixed selected recipient',
    () async {
      var sends = 0;
      final api = NeteaseApi(
        MockClient((request) async {
          sends++;
          expect(request.url.path, '/eapi/msg/private/send');
          final body = eapiBody(request);
          expect(body['userIds'], '[8]');
          expect(body['msg'], '你好😀');
          expect(body['type'], 'text');
          return response({
            'newMsgs': [
              {
                'id': 99,
                'msg': jsonEncode({'msg': '你好😀'}),
                'fromUser': {'userId': 7},
                'toUser': {'userId': 8},
              },
            ],
          });
        }),
      )..configure(session);
      final rows = await NeteaseMessagesRepository(
        NeteaseMusicRepository(api),
      ).sendText('8', '你好😀');
      expect(rows.single.id, '99');
      expect(sends, 1);
    },
  );
  test(
    'private pictures allocate, upload without cookies, then send picinfo',
    () async {
      final paths = <String>[];
      final bytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
      final api = NeteaseApi(
        MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/eapi/nos/token/alloc') {
            final body = eapiBody(request);
            expect(body['fileSize'], 4);
            expect(body['type'], 'image');
            return response({
              'result': {
                'bucket': 'yyimgs',
                'objectKey': 'fixture/image.jpg',
                'docId': '99',
                'token': 'nos-only',
              },
            });
          }
          if (request.url.host == 'nosup-hz1.127.net') {
            expect(request.headers['cookie'], isNull);
            expect(request.headers['x-nos-token'], 'nos-only');
            expect(request.bodyBytes, bytes);
            return response({});
          }
          expect(request.url.path, '/eapi/msg/private/send');
          final body = eapiBody(request);
          expect(body['type'], 'pic');
          final pic = jsonDecode('${body['picinfo']}') as Map;
          expect(pic['picIdStr'], '99');
          expect(pic['width'], 20);
          expect(pic['height'], 30);
          return response({'newMsgs': []});
        }),
      )..configure(session);
      await NeteaseMessagesRepository(
        NeteaseMusicRepository(api),
      ).sendPicture('8', bytes, 20, 30);
      expect(paths, [
        '/eapi/nos/token/alloc',
        '/yyimgs/fixture/image.jpg',
        '/eapi/msg/private/send',
      ]);
    },
  );
  test(
    'account switch during upload prevents sending a picture to another account',
    () async {
      late NeteaseApi api;
      api = NeteaseApi(
        MockClient((request) async {
          api.configure(null);
          return response({
            'result': {
              'bucket': 'yyimgs',
              'objectKey': 'x',
              'docId': '1',
              'token': 'x',
            },
          });
        }),
      )..configure(session);
      final repository = NeteaseMessagesRepository(NeteaseMusicRepository(api));
      await expectLater(
        repository.sendPicture(
          '8',
          Uint8List.fromList([255, 216, 255, 217]),
          1,
          1,
        ),
        throwsA(isA<MusicPlatformException>()),
      );
    },
  );
  test(
    'blacklist receipt is not shown as a delivered private message',
    () async {
      final api = NeteaseApi(
        MockClient(
          (_) async => response({
            'sendblacklist': [8],
          }),
        ),
      )..configure(session);
      await expectLater(
        NeteaseMessagesRepository(
          NeteaseMusicRepository(api),
        ).sendText('8', '你好'),
        throwsA(isA<MusicPlatformException>()),
      );
    },
  );
  test(
    'recent start is immediate once ready and duration excludes pause/buffering',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = ListeningSyncStore(db),
          clock = FakeClock(),
          feed = FakeFeed();
      final logs = <Map<String, dynamic>>[];
      var verifications = 0;
      final api = NeteaseApi(
        MockClient((request) async {
          if (request.url.path.endsWith('feedback/weblog')) {
            expect(request.url.host, 'clientlog.music.163.com');
            expect(request.headers['cookie'], contains('os=osx'));
            logs.add(
              Map<String, dynamic>.from(
                (jsonDecode('${eapiBody(request)['logs']}') as List).single
                    as Map,
              ),
            );
            return response({});
          }
          verifications++;
          expect(request.url.path, endsWith('/play-record/song/list'));
          return response({
            'data': {
              'list': [
                {
                  'playTime': clock.now.millisecondsSinceEpoch,
                  'data': {
                    'song': {'id': 17},
                  },
                },
              ],
            },
          });
        }),
      )..configure(session);
      feed.setTrack(song);
      feed.setState(true, false);
      final reporter = NeteaseListeningReporter(
        feed: feed,
        music: NeteaseMusicRepository(api),
        store: store,
        current: () => true,
        clock: clock,
        observeLifecycle: false,
        automaticTimers: false,
      );
      await reporter.settle();
      expect(logs, isEmpty);
      feed.setState(true, true);
      await reporter.settle();
      expect(logs.single['action'], 'startplay');
      expect((logs.single['json'] as Map).containsKey('time'), isFalse);
      clock.elapse(5000);
      reporter.checkpoint();
      await reporter.settle();
      expect(verifications, 1);
      expect(
        (await store.entries('netease:7'))
            .singleWhere((r) => r.kind == 'netease-startplay')
            .payload['cloudConfirmed'],
        isTrue,
      );
      feed.setState(false, true);
      clock.elapse(9000);
      feed.setState(true, false);
      clock.elapse(6000);
      feed.setState(true, true);
      clock.elapse(2000);
      feed.setTrack(null);
      await reporter.settle();
      expect(logs.map((l) => l['action']), ['startplay', 'play']);
      expect((logs.last['json'] as Map)['time'], 7);
      reporter.dispose();
      await reporter.settle();
      expect(logs, hasLength(2));
    },
  );
  test(
    'preview uses exact NetEase fallback through the production decision',
    () async {
      var fallbackRequests = 0;
      final musicApi = NeteaseApi(
        MockClient(
          (_) async => response({
            'data': [
              {
                'id': 17,
                'url': 'https://m1.music.126.net/preview.mp3',
                'level': 'standard',
                'time': 30000,
              },
            ],
          }),
        ),
      )..configure(session);
      final client = MockClient((request) async {
        expect(request.headers['cookie'], isNull);
        if (request.url.host == 'api.bugpk.com') {
          fallbackRequests++;
          expect(request.url.queryParameters['id'], '17');
          return response({
            'data': [
              {
                'id': 17,
                'url': 'https://m1.music.126.net/full.mp3',
                'level': 'standard',
              },
            ],
          });
        }
        return http.Response.bytes(
          [73, 68, 51, 0],
          206,
          headers: {'content-type': 'audio/mpeg'},
        );
      });
      final resolved = await resolveNeteaseTrack(
        music: NeteaseMusicRepository(musicApi),
        fallback: NeteaseFallbackResolver([
          BugpkNeteaseFallback(client),
        ], client),
        allowFallback: true,
        current: () => true,
        track: song,
        quality: PlatformAudioQuality.standard,
        requireQuality: true,
      );
      expect(resolved.id, song.id);
      expect(resolved.source, TrackSource.netease);
      expect(resolved.isPreview, isFalse);
      expect(resolved.availabilityMessage, contains('BugPk'));
      expect(fallbackRequests, 1);
    },
  );
  test(
    'BugPk outer URLs become HTTPS CDN URLs without sharing credentials',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.headers['cookie'], isNull);
        if (request.url.host == 'api.bugpk.com') {
          return response({
            'data': [
              {
                'id': '17',
                'url': 'https://music.163.com/song/media/outer/url?id=17.mp3',
                'level': 'standard',
              },
            ],
          });
        }
        expect(request.url.host, 'music.163.com');
        expect(request.followRedirects, isFalse);
        return http.Response(
          '',
          302,
          headers: {'location': 'http://m801.music.126.net/full.mp3'},
        );
      });
      final resolved = await BugpkNeteaseFallback(client).resolve(song);
      expect(resolved?.audioAsset, 'https://m801.music.126.net/full.mp3');
      expect(calls, 2);
    },
  );
  test('BugPk rejects foreign redirects without following them', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (request.url.host == 'api.bugpk.com') {
        return response({
          'data': [
            {
              'id': 17,
              'url': 'https://music.163.com/song/media/outer/url?id=17.mp3',
              'level': 'standard',
            },
          ],
        });
      }
      expect(request.url.host, 'music.163.com');
      return http.Response(
        '',
        302,
        headers: {'location': 'https://foreign.test/audio.mp3'},
      );
    });
    await expectLater(
      BugpkNeteaseFallback(client).resolve(song),
      throwsA(
        isA<NeteaseSourceFailure>().having(
          (e) => e.reason,
          'reason',
          'redirect_not_audio',
        ),
      ),
    );
    expect(calls, 2);
  });
  test(
    'bounded audio probing rejects an obviously short preview resource',
    () async {
      final client = MockClient(
        (_) async => http.Response.bytes(
          [73, 68, 51, 0],
          206,
          headers: {
            'content-type': 'audio/mpeg',
            'content-range': 'bytes 0-3/480000',
          },
        ),
      );
      expect(
        await probeAudio(
          client,
          'https://m1.music.126.net/trial.mp3',
          minimumBytes: 1500000,
        ),
        isFalse,
      );
    },
  );
  test(
    'selecting the next track while the old source is ready does not report a start',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final feed = FakeFeed(), clock = FakeClock();
      var starts = 0;
      final api = NeteaseApi(
        MockClient((r) async {
          final logs = jsonDecode('${eapiBody(r)['logs']}') as List;
          if ((logs.single as Map)['action'] == 'startplay') starts++;
          return response({});
        }),
      )..configure(session);
      feed.setTrack(song);
      feed.setState(true, true);
      final reporter = NeteaseListeningReporter(
        feed: feed,
        music: NeteaseMusicRepository(api),
        store: ListeningSyncStore(db),
        current: () => true,
        clock: clock,
        observeLifecycle: false,
        automaticTimers: false,
      );
      await reporter.settle();
      expect(starts, 1);
      feed.setTrack(
        Track.fromJson({
          ...song.toJson(),
          'id': 'netease_18',
          'platformSongId': '18',
        }),
      );
      await reporter.settle();
      expect(starts, 1);
      feed.setState(true, false);
      await reporter.settle();
      expect(starts, 1);
      feed.setState(true, true);
      await reporter.settle();
      expect(starts, 2);
      reporter.dispose();
      await reporter.settle();
    },
  );
  test(
    'together keeps reporting after its creation call and sends official invitation links',
    () async {
      final player = FakeTogetherPlayer();
      addTearDown(player.close);
      var inRoom = false, commands = 0, invitations = 0;
      final api = NeteaseApi(
        MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/status/get')) {
            return response({
              'data': {
                'inRoom': inRoom,
                if (inRoom) 'roomInfo': {'roomId': 'room-1', 'roomUsers': []},
              },
            });
          }
          if (path.endsWith('/room/create')) {
            inRoom = true;
            return response({
              'data': {
                'roomInfo': {'roomId': 'room-1'},
              },
            });
          }
          if (path.endsWith('/play/command/report')) {
            commands++;
            return response({});
          }
          if (path.endsWith('/msg/private/send')) {
            invitations++;
            final body = eapiBody(request);
            expect(body['userIds'], '[8]');
            expect(
              body['msg'],
              contains('https://st.music.163.com/listen-together/share/'),
            );
            return response({'newMsgs': []});
          }
          if (path.endsWith('/end/v2')) {
            inRoom = false;
            return response({
              'data': {'success': true},
            });
          }
          return response({'data': {}});
        }),
      )..configure(session);
      final music = NeteaseMusicRepository(api);
      final controller = NeteaseTogetherController(
        music: music,
        player: player,
        messages: NeteaseMessagesRepository(music),
        isCurrent: () => api.session?.credentialId == session.credentialId,
        automaticTimer: false,
      );
      await controller.invite(const NeteasePerson('8', '朋友'));
      expect(controller.active, isTrue);
      expect(invitations, 1);
      final previous = commands;
      player.commandController.add('pause');
      await controller.settle();
      expect(commands, previous + 1);
      await controller.tick();
      expect(controller.active, isTrue);
      await controller.end();
      expect(controller.active, isFalse);
      player.commandController.add('play');
      await controller.settle();
      expect(commands, previous + 1);
      controller.dispose();
    },
  );
  test('together link parsing rejects credentials or foreign hosts', () {
    expect(
      NeteaseTogetherInvitation.parse(
        'https://evil.test/listen-together/share/?roomId=a&inviterId=7',
      ),
      isNull,
    );
    expect(
      NeteaseTogetherInvitation.parse(
        'https://user@st.music.163.com/listen-together/share/?roomId=a&inviterId=7',
      ),
      isNull,
    );
    expect(
      NeteaseTogetherInvitation.parse(
        'https://st.music.163.com/listen-together/share/?roomId=a&inviterId=7',
      )?.room,
      'a',
    );
  });
  test(
    'all catalogue entries have task identities and automatic mechanics stay out of forms',
    () {
      final all =
          (jsonDecode(
                    File(
                      'assets/data/netease-full-catalog.json',
                    ).readAsStringSync(),
                  )
                  as Map)['entries']
              as List;
      final entries = all
          .map(
            (r) =>
                NeteaseEndpoint.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
      expect(entries, hasLength(305));
      expect(entries.map(neteaseWorkflowKey).toSet().length, lessThan(260));
      expect(
        entries
            .where((e) => e.category == '消息中心')
            .map(neteaseWorkflowKey)
            .toSet(),
        {'messages'},
      );
      expect(
        neteaseAutomaticFields,
        containsAll(['limit', 'offset', 'cursor', 'before']),
      );
      final content = NeteaseContent.parse({
        'data': {
          'userId': 1,
          'province': 430000,
          'birthday': -1,
          'nickname': '朋友',
        },
      }, '/user/account');
      expect(content.facts.values, isNot(contains('430000')));
      expect(content.facts.values, isNot(contains('-1')));
    },
  );
}
