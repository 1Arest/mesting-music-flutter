import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/persistence/playback_persistence_controller.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/auth/beta_account_choice.dart';
import 'package:mesting_music/features/auth/beta_entry_flow.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_session_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_crypto.dart';
import 'package:mesting_music/features/music_platform/netease/netease_login.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/shared/models/track.dart';

import 'support/deterministic_audio_player.dart';

const _kg = PlatformSession(userId: '7', token: 'test-kugou', nickname: '酷狗夹具');
const _ne = NeteaseSession(
  userId: '7',
  deviceId: 'test-device',
  cookies: {'MUSIC_U': 'test-netease'},
  nickname: '网易云夹具',
);

class _KugouStore implements PlatformSessionStore {
  PlatformSession? saved = _kg;
  @override
  Future<PlatformSession?> read() async => saved;
  @override
  Future<void> write(PlatformSession session) async {
    saved = session;
  }

  @override
  Future<void> clear() async {
    saved = null;
  }
}

class _NeteaseStore implements NeteaseSessionStore {
  NeteaseSession? saved = _ne;
  bool fail = false;
  @override
  Future<NeteaseSession?> read() async => saved;
  @override
  Future<void> write(NeteaseSession session) async {
    if (fail) throw StateError('test storage failure');
    saved = session;
  }

  @override
  Future<void> clear() async {
    saved = null;
  }
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

http.Response _json(Object data, {Map<String, String>? headers}) =>
    http.Response(
      jsonEncode(data),
      200,
      headers: {'content-type': 'application/json', ...?headers},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('two platform accounts', () {
    late _KugouStore kg;
    late _NeteaseStore ne;
    late NeteaseApi api;
    late MusicPlatformApi kugouApi;
    late SharedPreferences preferences;
    late ProviderContainer container;
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        BetaAccountChoiceController.preferenceKey: 'kugou',
      });
      preferences = await SharedPreferences.getInstance();
      kg = _KugouStore();
      ne = _NeteaseStore();
      api = NeteaseApi(MockClient((_) async => _json({'code': 200})));
      kugouApi = MusicPlatformApi(
        server: _Server(),
        client: MockClient((_) async => _json({'status': 1, 'data': {}})),
      );
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          platformSessionStoreProvider.overrideWithValue(kg),
          neteaseSessionStoreProvider.overrideWithValue(ne),
          neteaseApiProvider.overrideWithValue(api),
          musicPlatformApiProvider.overrideWithValue(kugouApi),
        ],
      );
      await container.read(platformAccountProvider.future);
    });
    tearDown(() => container.dispose());

    test('equal numeric IDs have separate owners and transports', () async {
      final controller = container.read(platformAccountProvider.notifier);
      final before = <String>[];
      controller.preparePlatformSwitch = (owner) async {
        before.add(
          '${container.read(platformAccountProvider).value?.ownerId}->$owner',
        );
      };
      await controller.switchPlatform(MusicPlatform.netease);
      expect(before, ['kugou:7->netease:7']);
      expect(container.read(activeLibraryOwnerProvider), 'netease:7');
      expect(kugouApi.session, isNull);
      expect(api.session?.userId, '7');
      expect(kg.saved?.token, _kg.token);
      await controller.switchPlatform(MusicPlatform.kugou);
      expect(container.read(activeLibraryOwnerProvider), 'kugou:7');
      expect(kugouApi.session?.token, _kg.token);
      expect(api.cookies, isEmpty);
      expect(ne.saved?.cookies['MUSIC_U'], 'test-netease');
    });

    test(
      'logout deletes only active credential and retains the other login',
      () async {
        final c = container.read(platformAccountProvider.notifier);
        await c.switchPlatform(MusicPlatform.netease);
        await c.signOut();
        expect(ne.saved, isNull);
        expect(kg.saved, _kg);
        expect(container.read(platformAccountProvider).value, isNull);
        expect(api.cookies, isEmpty);
        expect(
          container.read(betaAccountChoiceProvider),
          BetaAccountChoice.guest,
        );
      },
    );

    test('adding another login does not replay the welcome tour', () async {
      final flow = container.read(betaEntryFlowProvider.notifier);
      await flow.finish();
      await container.read(platformAccountProvider.notifier).acceptNetease(_ne);
      expect(container.read(betaEntryFlowProvider), BetaEntryStage.app);
      expect(kg.saved, _kg);
    });

    test(
      'failed credential persistence leaves the active account intact',
      () async {
        ne.fail = true;
        await expectLater(
          container.read(platformAccountProvider.notifier).acceptNetease(_ne),
          throwsStateError,
        );
        expect(
          container.read(platformAccountProvider).value?.ownerId,
          'kugou:7',
        );
        expect(kugouApi.session?.token, _kg.token);
        expect(api.cookies, isEmpty);
      },
    );

    test(
      'last selected platform can be restored without resurrecting Kugou',
      () async {
        await container
            .read(platformAccountProvider.notifier)
            .switchPlatform(MusicPlatform.netease);
        final restarted = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            platformSessionStoreProvider.overrideWithValue(kg),
            neteaseSessionStoreProvider.overrideWithValue(ne),
            neteaseApiProvider.overrideWithValue(api),
            musicPlatformApiProvider.overrideWithValue(kugouApi),
          ],
        );
        addTearDown(restarted.dispose);
        expect(
          (await restarted.read(platformAccountProvider.future))?.ownerId,
          'netease:7',
        );
        expect(kugouApi.session, isNull);
      },
    );
  }, skip: !DistributionChannel.isBeta);

  test(
    'switching preserves per-owner queues, positions and paused state',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final player = DeterministicAudioPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      final persistence = PlaybackPersistenceController(
        database: db,
        audioHandler: handler,
      );
      final a = Track(
        id: 'kugou_A',
        title: 'A',
        artist: '',
        album: '',
        duration: const Duration(minutes: 4),
        audioAsset: 'file:///test-music-a.mp3',
        coverAsset: '',
        lyricsAsset: '',
        source: TrackSource.local,
      );
      final b = Track(
        id: 'netease_2',
        title: 'B',
        artist: '',
        album: '',
        duration: const Duration(minutes: 4),
        audioAsset: 'file:///test-music-b.mp3',
        coverAsset: '',
        lyricsAsset: '',
        source: TrackSource.local,
      );
      try {
        await persistence.activateOwner('kugou:7');
        await handler.replaceQueue([a], autoplay: false);
        await handler.seek(const Duration(seconds: 42));
        await handler.play();
        await persistence.preparePlatformSwitch('netease:7');
        expect(player.active, false);
        await persistence.activateOwner('netease:7');
        expect(handler.mediaItem.value, isNull);
        await handler.replaceQueue([b], autoplay: false);
        await handler.seek(const Duration(seconds: 17));
        await persistence.preparePlatformSwitch('kugou:7');
        await persistence.activateOwner('kugou:7');
        expect(handler.mediaItem.value?.id, a.id);
        expect(handler.currentPosition, const Duration(seconds: 42));
        expect(player.active, false);
        expect(handler.playbackOrder, const PlaybackOrder());
        await persistence.preparePlatformSwitch('netease:7');
        await persistence.activateOwner('netease:7');
        expect(handler.mediaItem.value?.id, b.id);
        expect(handler.currentPosition, const Duration(seconds: 17));
        expect(player.active, false);
      } finally {
        await persistence.dispose();
        await handler.debugDispose();
        await db.close();
      }
    },
  );

  test(
    'NetEase rejected or late responses cannot rewrite an active cookie jar',
    () async {
      final pending = Completer<http.Response>();
      final api = NeteaseApi(MockClient((_) => pending.future));
      api.configure(_ne);
      final request = api.call('/search', query: {'keywords': 'fixture'});
      api.configure(null);
      pending.complete(
        _json(
          {'code': 200, 'result': {}},
          headers: {'set-cookie': 'MUSIC_U=stale; Path=/'},
        ),
      );
      await expectLater(request, throwsA(isA<MusicPlatformException>()));
      expect(api.cookies, isEmpty);
    },
  );

  test(
    'old repositories reject a replaced login before dispatching writes',
    () async {
      var requests = 0;
      final api = NeteaseApi(
        MockClient((_) async {
          requests++;
          return _json({'code': 200});
        }),
      );
      api.configure(_ne);
      final music = NeteaseMusicRepository(api);
      api.configure(
        const NeteaseSession(
          userId: '7',
          deviceId: 'new-device',
          cookies: {'MUSIC_U': 'replacement'},
        ),
      );
      await expectLater(
        music.call('/like', {'id': '1'}),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(requests, 0);
    },
  );

  test(
    'login jar is private and QR success alone can commit its cookies',
    () async {
      final api = NeteaseApi(
        MockClient((request) async {
          if (request.url.path.endsWith('/unikey')) {
            return _json({'code': 200, 'unikey': 'fixture-key'});
          }
          if (request.url.path.endsWith('/client/login')) {
            return _json(
              {'code': 803},
              headers: {
                'set-cookie':
                    'MUSIC_U=login-cookie; Path=/, __csrf=test-csrf; Path=/',
              },
            );
          }
          return _json({
            'code': 200,
            'profile': {'userId': 7, 'nickname': 'fixture'},
          });
        }),
      );
      final service = NeteaseLoginService(api);
      final qr = await service.createQr();
      final session = await service.poll(qr);
      expect(session?.identity.ownerId, 'netease:7');
      expect(session?.cookies['MUSIC_U'], 'login-cookie');
      expect(api.cookies, isEmpty);
    },
  );

  test('audio permissions and delivered quality stay authoritative', () async {
    var denied = true;
    final api = NeteaseApi(
      MockClient(
        (_) async => _json({
          'code': 200,
          'data': [
            {
              'url': denied ? null : 'https://example.invalid/audio.mp3',
              'level': 'standard',
            },
          ],
        }),
      ),
    )..configure(_ne);
    final music = NeteaseMusicRepository(api);
    final track = NeteaseMusicRepository.track({'id': 1, 'name': 'fixture'})!;
    await expectLater(
      music.resolve(track, PlatformAudioQuality.standard),
      throwsA(isA<MusicPlatformException>()),
    );
    denied = false;
    await expectLater(
      music.resolve(track, PlatformAudioQuality.lossless, requireQuality: true),
      throwsA(isA<MusicPlatformException>()),
    );
    final resolved = await music.resolve(track, PlatformAudioQuality.standard);
    expect(resolved.playbackQuality, '128');
    expect(resolved.source, TrackSource.netease);
  });

  test('large playlists keep server order and hydrate omitted songs', () async {
    final api = NeteaseApi(
      MockClient(
        (req) async => req.url.path.contains('playlist/detail')
            ? _json({
                'code': 200,
                'playlist': {
                  'trackIds': [
                    {'id': 2},
                    {'id': 1},
                  ],
                  'tracks': [
                    {'id': 1, 'name': 'one'},
                  ],
                },
              })
            : _json({
                'code': 200,
                'songs': [
                  {'id': 2, 'name': 'two'},
                ],
              }),
      ),
    )..configure(_ne);
    final rows = await NeteaseMusicRepository(api).playlist('99');
    expect(rows.map((t) => t.id), ['netease_2', 'netease_1']);
  });

  test('protocol golden vectors agree with independent Node crypto', () {
    final fixtures =
        jsonDecode(
              File(
                'test/fixtures/netease-protocol-vectors.json',
              ).readAsStringSync(),
            )
            as Map;
    final payload = Map<String, Object?>.from(fixtures['payload'] as Map);
    expect(NeteaseCrypto.eapi('/api/test', payload), fixtures['eapi']);
    expect(
      NeteaseCrypto.weapi(payload, secret: 'abcdefghijklmnop'),
      fixtures['weapi'],
    );
  });
}
