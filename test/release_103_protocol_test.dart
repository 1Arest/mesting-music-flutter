import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_profile_repository.dart';
import 'package:mesting_music/features/music_platform/domain/platform_profile.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/domain/platform_regions.dart';
import 'package:mesting_music/features/music_platform/data/platform_effects_repository.dart';
import 'package:mesting_music/features/music_platform/data/platform_mv_repository.dart';
import 'package:mesting_music/features/app_update/domain/release_history.dart';
import 'package:mesting_music/shared/models/track.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

const owner = PlatformSession(
  userId: '103-profile',
  token: 'synthetic-token',
  nickname: '原昵称',
);
http.Response response(Map<String, dynamic> data) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), 200);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MusicPlatformApi api(
    Future<Map<String, dynamic>> Function(http.Request) action,
  ) => MusicPlatformApi(
    server: _Server(),
    client: MockClient((request) async => response(await action(request))),
  )..session = owner;

  test(
    'profile dirty fields preserve absent server values and explicit clears',
    () {
      const initial = PlatformProfileInfo(
        '原昵称',
        '',
        signature: '原签名',
        birthday: '2000-01-02',
        sex: 1,
        province: '四川省',
        city: '成都市',
      );
      expect(
        profileChanges(initial, nickname: '原昵称', signature: '原签名'),
        isEmpty,
      );
      expect(
        profileChanges(
          initial,
          nickname: '新昵称',
          signature: '',
          birthday: '',
          sex: 0,
          province: '四川省',
          city: '绵阳市',
        ),
        {
          'nickname': '新昵称',
          'signature': '',
          'birthday': '',
          'sex': 0,
          'city': '绵阳市',
        },
      );
      expect(
        profileChanges(
          const PlatformProfileInfo('原昵称', ''),
          nickname: '原昵称',
          signature: '',
        ),
        isEmpty,
      );
    },
  );
  test(
    'profile parser preserves nullable gender, aliases and calendar birthday',
    () {
      final profile = PlatformProfileInfo.fromJson({
        'data': {
          'nickname': '测试用户',
          'usersign': '测试签名',
          'gender': '0',
          'birthday': '2001-02-03',
          'province_name': '四川省',
          'city_name': '成都市',
        },
      }, owner);
      expect(profile.sex, 0);
      expect(profile.signature, '测试签名');
      expect(profile.birthday, '2001-02-03');
      expect(profile.province, '四川省');
      expect(PlatformProfileInfo.fromJson({'data': {}}, owner).sex, isNull);
      expect(PlatformProfileInfo.normalizeBirthday('0'), isNull);
    },
  );
  test(
    'profile and avatar writes use JSON bodies, never image/query parameters',
    () async {
      final requests = <http.Request>[];
      final transport = api((r) async {
        requests.add(r);
        return {
          'status': 1,
          'error_code': 0,
          'pic': 'https://img.example/avatar.png',
        };
      });
      final repository = PlatformProfileRepository(transport);
      await repository.save(owner, {
        'nickname': '新昵称',
        'sex': 0,
        'signature': '',
      });
      final image = Uint8List.fromList([
        0x89,
        0x50,
        0x4e,
        0x47,
        13,
        10,
        26,
        10,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(
        await repository.uploadAvatar(owner, image),
        'https://img.example/avatar.png',
      );
      expect(requests.map((r) => r.url.path), [
        '/user/update',
        '/user/update/avatar',
      ]);
      for (final request in requests) {
        expect(request.method, 'POST');
        expect(request.url.queryParameters.containsKey('imgFile'), false);
        expect(request.url.queryParameters.containsKey('nickname'), false);
        expect(request.headers['content-type'], contains('application/json'));
        expect(
          request.headers['authorization'],
          contains('userid=103-profile'),
        );
      }
      expect(jsonDecode(requests[0].body), {
        'nickname': '新昵称',
        'sex': 0,
        'signature': '',
      });
      expect(jsonDecode(requests[1].body)['imgFile'], base64Encode(image));
    },
  );
  test(
    'profile write never retries or leaks an echoed account payload',
    () async {
      var writes = 0;
      final repository = PlatformProfileRepository(
        api((_) async {
          writes++;
          return {
            'status': 0,
            'error_code': 20010,
            'msg': 'synthetic-token FULL_DRAFT',
          };
        }),
      );
      try {
        await repository.save(owner, {'nickname': '新昵称'});
        fail('Expected rejection');
      } catch (error) {
        expect('$error', contains('20010'));
        expect('$error', isNot(contains('synthetic-token')));
        expect('$error', isNot(contains('FULL_DRAFT')));
      }
      expect(writes, 1);
    },
  );
  test(
    'changed account rejects profile write before making a request',
    () async {
      var writes = 0;
      final transport =
          api((_) async {
              writes++;
              return {'status': 1};
            })
            ..session = const PlatformSession(
              userId: 'another',
              token: 'another-fixture',
            );
      await expectLater(
        PlatformProfileRepository(transport).save(owner, {'nickname': '新昵称'}),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(writes, 0);
    },
  );
  test(
    'account changed while a profile request was pending rejects stale response',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      final transport = api((_) => gate.future);
      final pending = PlatformProfileRepository(
        transport,
      ).save(owner, {'nickname': '新昵称'});
      await Future<void>.delayed(Duration.zero);
      transport.session = const PlatformSession(
        userId: 'another',
        token: 'other-fixture',
      );
      gate.complete({'status': 1});
      await expectLater(pending, throwsA(isA<MusicPlatformException>()));
    },
  );
  test(
    'empty profile changes make no upstream write and unsupported fields fail',
    () async {
      var writes = 0;
      final repository = PlatformProfileRepository(
        api((_) async {
          writes++;
          return {'status': 1};
        }),
      );
      await repository.save(owner, {});
      await expectLater(
        repository.save(owner, {'memo': 'outside scope'}),
        throwsArgumentError,
      );
      expect(writes, 0);
    },
  );
  test(
    'avatar rejects unsupported and oversized images before network',
    () async {
      var writes = 0;
      final repository = PlatformProfileRepository(
        api((_) async {
          writes++;
          return {'status': 1};
        }),
      );
      await expectLater(
        repository.uploadAvatar(owner, Uint8List(32)),
        throwsA(isA<MusicPlatformException>()),
      );
      await expectLater(
        repository.uploadAvatar(owner, Uint8List(4 * 1024 * 1024)),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(writes, 0);
    },
  );
  test(
    'offline region picker has real cities and municipalities are cities',
    () async {
      final regions = await loadMusicRegions();
      expect(regions.length, 31);
      expect(
        regions.firstWhere((p) => p.name == '北京市').cities.map((c) => c.name),
        ['北京市'],
      );
      expect(
        regions.firstWhere((p) => p.name == '四川省').cities.map((c) => c.name),
        contains('成都市'),
      );
    },
  );
  test(
    'effect parsing excludes VIP/VPF-only and maps free presets honestly',
    () {
      final bass = MusicSoundEffect.parse({
        'id': 1,
        'name': '重低音',
        'sound': 'https://sample.example/free.irs',
        'privilege': 0,
      });
      expect(bass!.preset, '重低音');
      expect(
        MusicSoundEffect.parse({'id': 2, 'name': 'VIP', 'vpfsize': 100}),
        isNull,
      );
      expect(
        MusicSoundEffect.parse({
          'id': 3,
          'name': 'VIP',
          'sound': 'https://sample.example/free.irs',
          'privilege': 1,
        }),
        isNull,
      );
      expect(
        MusicSoundEffect.parse({
          'model_id': 4,
          'sound': {'name': '人声', 'sound': 'https://sample.example/free.irs'},
        })!.preset,
        '人声',
      );
    },
  );
  test(
    'effects pagination uses raw rows, not the count after VIP filtering',
    () async {
      final repository = PlatformEffectsRepository(
        api((r) async {
          expect(r.url.path, '/get/model');
          expect(r.url.queryParameters['sort'], '4');
          return {
            'data': List.generate(
              30,
              (i) => {'id': i + 1, 'name': 'VIP', 'vpfsize': 100},
            ),
          };
        }),
      );
      final page = await repository.list(
        MusicEffectsCatalog.community,
        newest: true,
      );
      expect(page.items, isEmpty);
      expect(page.hasMore, true);
    },
  );
  test(
    'headphone and artist effect routes preserve selected brand and page',
    () async {
      final paths = <String>[];
      final repository = PlatformEffectsRepository(
        api((r) async {
          paths.add(r.url.path);
          if (r.url.path.endsWith('/detail')) {
            expect(r.url.queryParameters['brand_id'], '12');
          }
          return {
            'data': {'list': []},
          };
        }),
      );
      await repository.list(MusicEffectsCatalog.earphone);
      await repository.list(MusicEffectsCatalog.earphone, brandId: '12');
      await repository.list(MusicEffectsCatalog.artist, page: 2);
      expect(paths, [
        '/effects/match',
        '/effects/brand/detail',
        '/effects/artist',
      ]);
    },
  );
  test('an explicit rejected status cannot be overridden by a zero code', () async {
    final repository = PlatformProfileRepository(api((_) async => {'status': 0, 'code': 0, 'error_code': 0}));
    await expectLater(repository.save(owner, {'nickname': '新昵称'}), throwsA(isA<MusicPlatformException>()));
  });
  const track = Track(
    id: 'kugou_audiohash',
    title: '测试歌曲',
    artist: '测试歌手',
    album: '',
    duration: Duration(minutes: 3),
    audioAsset: 'https://sample.example/audio.mp3',
    coverAsset: '',
    lyricsAsset: '',
    source: TrackSource.kugou,
    platformSongId: '12345',
  );
  test(
    'MV uses album recording ID, video ID and video hash on separate routes',
    () async {
      final requests = <http.Request>[];
      final repository = PlatformMvRepository(
        api((r) async {
          requests.add(r);
          return switch (r.url.path) {
            '/kmr/audio/mv' => {
              'data': [
                [
                  {
                    'video_id': 55,
                    'mv_name': '官方 MV',
                    'h264': {'hd_hash': 'video-hd'},
                  },
                ],
              ],
            },
            '/video/detail' => {
              'data': [
                {'fhd_hash': 'video-fullhd'},
              ],
            },
            '/video/url' => {
              'data': {
                'video-hd': {
                  'downurl': 'http://fsmvpc.tx.kugou.com/video.mp4',
                  'backupdownurl': ['https://media.example/backup.mp4'],
                },
              },
            },
            _ => throw StateError('Unexpected route'),
          };
        }),
      );
      final mv = (await repository.lookup(track))!;
      expect(mv.qualities.map((q) => q.hash), ['video-hd', 'video-fullhd']);
      final urls = await repository.urls(mv.qualities.first);
      expect(urls.length, 2);
      expect(requests[0].url.queryParameters['album_audio_id'], '12345');
      expect(requests[1].url.queryParameters['id'], '55');
      expect(requests[2].url.queryParameters['hash'], 'video-hd');
    },
  );
  test(
    'MV URI parsing rejects another hash, arbitrary cleartext and file URLs',
    () {
      expect(
        PlatformMvRepository.parseUrls({
          'data': {
            'another-hash': {'downurl': 'https://media.example/wrong.mp4'},
          },
        }, 'wanted'),
        isEmpty,
      );
      expect(
        PlatformMvRepository.parseUrls({
          'data': {
            'wanted': {
              'downurl': 'http://unrelated.example/a.mp4',
              'backupdownurl': 'file:///private',
            },
          },
        }, 'wanted'),
        isEmpty,
      );
    },
  );
  test(
    'local song and absent MV never manufacture a playable source',
    () async {
      var requests = 0;
      final repository = PlatformMvRepository(
        api((_) async {
          requests++;
          return {'data': []};
        }),
      );
      expect(
        await repository.lookup(
          Track.fromJson({...track.toJson(), 'source': 'local'}),
        ),
        isNull,
      );
      expect(requests, 0);
      expect(await repository.lookup(track), isNull);
      expect(requests, 1);
    },
  );
  test(
    'release notes are exact-version data and unknown future notes stay absent',
    () {
      expect(notesForMusicVersion('1.0.3').length, 6);
      expect(notesForMusicVersion('v1.0.2'), isNotEmpty);
      expect(notesForMusicVersion('9.9.9'), isEmpty);
    },
  );
}
