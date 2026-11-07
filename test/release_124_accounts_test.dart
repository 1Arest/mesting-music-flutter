import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/diagnostics/diagnostic_activity.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/embedded_kugou_music_source.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_rewards_repository.dart';
import 'package:mesting_music/features/music_platform/domain/platform_rewards.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/retained_kugou_scope.dart';
import 'package:mesting_music/features/music_platform/platform_rewards_provider.dart';
import 'package:mesting_music/features/music_platform/netease/netease_fallback.dart';
import 'package:mesting_music/features/music_platform/netease/netease_track_sources.dart';
import 'package:mesting_music/features/music_platform/netease/netease_playback_options.dart';
import 'package:mesting_music/features/music_platform/netease/fallback/netease_kugou_account_source.dart';
import 'package:mesting_music/shared/models/track.dart';

const _kugou = PlatformSession(
  userId: 'kg',
  token: 'fixture-kg',
  vipToken: 'fixture-vip',
);
const _net = PlatformSession(
  userId: 'net',
  token: 'fixture-net',
  platform: MusicPlatform.netease,
);
const _song = Track(
  id: 'netease_1',
  title: '原曲',
  artist: '歌手',
  album: '专辑',
  duration: Duration(seconds: 180),
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.netease,
);

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _net;
  void select(PlatformSession? next) => state = AsyncData(next);
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12400');
}

class _Rewards implements PlatformRewardService {
  int signs = 0, ads = 0;
  Completer<RewardOutcome>? pending;
  @override
  Future<RewardSnapshot> load(PlatformSession owner) async =>
      RewardSnapshot(now: DateTime(2026, 10, 31));
  @override
  Future<RewardOutcome> signIn(
    PlatformSession owner,
    DateTime day, {
    RewardVerifier? verify,
  }) async {
    signs++;
    return pending == null
        ? const RewardOutcome(true, 'confirmed', signed: true)
        : pending!.future;
  }

  @override
  Future<RewardOutcome> listen(PlatformSession owner) async =>
      const RewardOutcome(true, 'confirmed');
  @override
  Future<RewardOutcome> ad(PlatformSession owner) async {
    ads++;
    return const RewardOutcome(true, 'confirmed');
  }
}

Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

List<int> _flac({int rate = 44100, int depth = 16, int seconds = 180}) {
  final bytes = List<int>.filled(1024, 0)..setRange(0, 4, 'fLaC'.codeUnits);
  bytes[7] = 34;
  var packed =
      (rate << 44) | (1 << 41) | ((depth - 1) << 36) | (rate * seconds);
  for (var at = 25; at >= 18; at--) {
    bytes[at] = packed & 255;
    packed >>= 8;
  }
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<({ProviderContainer container, _Rewards service})> setup({
    bool automatic = true,
    bool diagnostic = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      PlatformRewardsController.autoSignInKey: automatic,
    });
    final prefs = await SharedPreferences.getInstance();
    final service = _Rewards();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformAccountProvider.overrideWith(_Account.new),
        savedKugouSessionProvider.overrideWith((ref) async => _kugou),
        platformRewardServiceProvider.overrideWithValue(service),
        platformRewardDelayProvider.overrideWithValue(
          (_, cancelled) => cancelled,
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(platformAccountProvider.future);
    await container.read(savedKugouSessionProvider.future);
    if (diagnostic) {
      container.read(diagnosticActivityProvider.notifier).setRunning(true);
    }
    container.listen(platformRewardsProvider, (_, _) {});
    await _flush();
    return (container: container, service: service);
  }

  test(
    'NetEase playback uses retained Kugou automatic sign-in without changing current account',
    () async {
      final (:container, :service) = await setup();
      expect(service.signs, 1);
      expect(container.read(platformAccountProvider).value, same(_net));
      expect(container.read(platformRewardsProvider).ownerId, 'kg');
      await container.read(platformRewardsProvider.notifier).signIn();
      expect(service.signs, 1, reason: 'confirmed account/day is deduplicated');
    },
  );
  test('diagnostic startup suppresses auto and manual reward writes', () async {
    final (:container, :service) = await setup(diagnostic: true);
    expect(service.signs, 0);
    expect(
      (await container.read(platformRewardsProvider.notifier).signIn()).success,
      false,
    );
    expect(
      (await container.read(platformRewardsProvider.notifier).listen()).success,
      false,
    );
    expect(service.signs, 0);
  });
  test('diagnostic startup cancels waiting advertisements', () async {
    final (:container, :service) = await setup(automatic: false);
    final operation = container.read(platformRewardsProvider.notifier).ads();
    await _flush();
    expect(service.ads, 1);
    container.read(diagnosticActivityProvider.notifier).setRunning(true);
    await operation;
    expect(service.ads, 1);
  });
  test(
    'platform switching retains the same reward operation and independent identity',
    () async {
      final (:container, :service) = await setup(automatic: false);
      service.pending = Completer<RewardOutcome>();
      final operation = container
          .read(platformRewardsProvider.notifier)
          .signIn();
      await _flush();
      (container.read(platformAccountProvider.notifier) as _Account).select(
        _kugou,
      );
      await _flush();
      (container.read(platformAccountProvider.notifier) as _Account).select(
        _net,
      );
      await _flush();
      service.pending!.complete(
        const RewardOutcome(true, 'confirmed', signed: true),
      );
      expect((await operation).success, true);
      expect(
        container.read(platformRewardsProvider).signedDates,
        contains('2026-10-31'),
      );
    },
  );
  test('retained account removal invalidates late reward results', () async {
    final (:container, :service) = await setup(automatic: false);
    service.pending = Completer<RewardOutcome>();
    final operation = container.read(platformRewardsProvider.notifier).signIn();
    await _flush();
    container.read(retainedKugouMutationProvider.notifier).publish(null);
    await _flush();
    service.pending!.complete(
      const RewardOutcome(true, 'confirmed', signed: true),
    );
    expect((await operation).success, false);
    expect(container.read(platformRewardsProvider).ownerId, isNull);
  });
  test(
    'account source is explicitly selectable independently of public source',
    () {
      expect(
        NeteaseTrackSource.accountKugou.adapter,
        AccountKugouFallback.sourceLabel,
      );
      expect(
        NeteaseTrackSource.accountKugou.adapter,
        isNot(NeteaseTrackSource.kugou.adapter),
      );
    },
  );
  for (final (rate, depth, hiRes) in [(44100, 16, false), (96000, 24, true)]) {
    test(
      'actual FLAC STREAMINFO establishes $rate/$depth rather than requested tier',
      () async {
        final client = MockClient(
          (_) async => http.Response.bytes(
            _flac(rate: rate, depth: depth),
            206,
            headers: {
              'content-type': 'audio/flac',
              'content-range': 'bytes 0-1023/10000000',
            },
          ),
        );
        final probe = await inspectNeteaseAudio(
          client,
          'https://cdn.example/audio',
          expectedDuration: _song.duration,
          requireLossless: true,
        );
        expect(probe.playable, true);
        expect(probe.sampleRate, rate);
        expect(probe.bitsPerSample, depth);
        expect(probe.hiRes, hiRes);
      },
    );
  }
  test(
    'account fallback sends only Kugou authorization and keeps original NetEase song identity',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.host == 'cdn.example') {
          expect(
            request.headers.keys.any((k) => k.toLowerCase() == 'authorization'),
            false,
          );
          return http.Response.bytes(
            _flac(),
            206,
            headers: {
              'content-type': 'audio/flac',
              'content-range': 'bytes 0-1023/10000000',
            },
          );
        }
        expect(
          request.headers['Authorization'] ?? request.headers['authorization'],
          contains('token=fixture-kg'),
        );
        expect(
          request.headers['Authorization'] ?? request.headers['authorization'],
          isNot(contains('fixture-net')),
        );
        return http.Response.bytes(
          utf8.encode(
            jsonEncode(
              request.url.path == '/search'
                  ? {
                      'data': {
                        'lists': [
                          {
                            'hash': 'abc',
                            'songname': '原曲',
                            'singername': '歌手',
                            'album_name': '专辑',
                            'duration': 180,
                          },
                        ],
                      },
                    }
                  : {
                      'data': {
                        'url': 'https://cdn.example/audio',
                        'priv_status': 1,
                        'quality': 'high',
                        'file_size': 10000000,
                      },
                    },
            ),
          ),
          200,
        );
      });
      final api = MusicPlatformApi(server: _Server(), client: client)
        ..session = _kugou;
      final source = AccountKugouFallback(
        EmbeddedKugouMusicSource(client, api),
        current: () => true,
      );
      final diagnostics = NeteaseFallbackDiagnostics();
      final resolver = NeteaseFallbackResolver(
        [source],
        client,
        diagnostics: diagnostics,
        options: const NeteasePlaybackOptions(diagnostics: true),
      );
      final result = await resolver.resolve(
        _song.copyWith(playbackQuality: 'flac'),
        current: () => true,
      );
      expect(result, isNotNull, reason: diagnostics.json);
      expect(result!.id, _song.id);
      expect(result.source, TrackSource.netease);
      expect(
        result.playbackQuality,
        'flac',
        reason: '16-bit stream cannot claim Hi-Res',
      );
      expect(requests.any((r) => r.url.path == '/song/url/new'), true);
    },
  );
  test('a revoked account never starts the next fallback request', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    });
    final api = MusicPlatformApi(server: _Server(), client: client)
      ..session = _kugou;
    final source = AccountKugouFallback(
      EmbeddedKugouMusicSource(client, api),
      current: () => false,
    );
    await expectLater(
      source.search(_song),
      throwsA(isA<NeteaseSourceFailure>()),
    );
    expect(calls, 0);
  });
}
