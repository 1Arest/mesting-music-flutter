import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/library/data/library_repository.dart';
import 'package:mesting_music/features/library/data/favorite_track_window.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/platform_profile_provider.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_rewards_provider.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_library_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_account_overview.dart';
import 'package:mesting_music/features/music_platform/netease/netease_connection_models.dart';
import 'package:mesting_music/features/music_platform/netease/netease_user_providers.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint_providers.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_unread.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';

const profileFixtureCover =
    'assets/images/theme_playlists/shinchan/cover-01.jpg';

class SyntheticProfileAccount extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    userId: '7001',
    token: 'fixture-only',
    nickname: '固定测试账号',
    platform: MusicPlatform.netease,
  );
}

/// Complete NetEase-shaped My-page fixture. It cannot reach the network:
/// API replies use MockClient and every visible image is a bundled asset.
/// Shared by host interaction tests and the future isolated native workload.
class PersonalProfileFixture {
  PersonalProfileFixture._(
    this.container,
    this.database,
    this.library,
    this.client,
  );
  final ProviderContainer container;
  final AppDatabase database;
  final NeteaseLibraryRepository library;
  final http.Client client;
  final favorites = StreamController<List<Track>>.broadcast();
  List<Track> tracks = List.generate(
    674,
    (i) => Track(
      id: 'netease_${8000 + i}',
      title: '测试歌曲 $i',
      artist: '合成数据',
      album: '固定样本',
      duration: const Duration(minutes: 4),
      audioAsset: '',
      lyricsAsset: '',
      source: TrackSource.netease,
      provider: '网易云',
      coverAsset: profileFixtureCover,
    ),
  );

  static Future<PersonalProfileFixture> create({
    NeteaseMusicRepository? musicRepository,
    LibraryRepository? browsingLibrary,
    FavoriteTrackWindow? favoritesWindow,
    MestingAudioHandler? audioHandler,
    PlatformAccountController Function()? accountFactory,
    List<Override> extraOverrides = const [],
    NeteasePersonalStats personalStats = const NeteasePersonalStats(
      following: 9,
      followers: 4,
      ownerId: 'netease:7001',
    ),
    OfficialFootprintSource? footprintSource,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final database = AppDatabase(NativeDatabase.memory());
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'code': 200,
          'playlist': [
            for (final id in [99, 100, 200, 300, 400])
              {
                'id': id,
                'name': '测试歌单 $id',
                'specialType': id == 99 ? 5 : 0,
                'creator': {'userId': id <= 200 ? 7001 : 7002},
              },
          ],
          'more': false,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final api = NeteaseApi(client)
      ..configure(
        const NeteaseSession(
          userId: '7001',
          cookies: {'MUSIC_U': 'fixture-only'},
          deviceId: 'fixture',
        ),
      );
    final music = NeteaseMusicRepository(api);
    final library = NeteaseLibraryRepository(
      database,
      music: music,
      identity: const PlatformSession(
        userId: '7001',
        token: 'fixture-only',
        platform: MusicPlatform.netease,
      ),
    );
    // Seed the real classification snapshot using only the mocked protocol.
    await library.getPlaylist('ne:99');
    late PersonalProfileFixture fixture;
    final container = ProviderContainer(
      overrides: [
        if (audioHandler != null)
          audioHandlerProvider.overrideWithValue(audioHandler),
        sharedPreferencesProvider.overrideWithValue(prefs),
        // This profile fixture owns synthetic browsing data, not a platform
        // keystore or live automatic rewards. Reward controller/UI acceptance
        // uses its own explicit service fixtures in release_159_* tests.
        neteaseRewardServiceProvider.overrideWith((ref) async => null),
        platformAccountProvider.overrideWith(
          accountFactory ?? SyntheticProfileAccount.new,
        ),
        neteaseMusicRepositoryProvider.overrideWithValue(
          musicRepository ?? music,
        ),
        platformProfileProvider.overrideWith(
          (ref) async => const PlatformProfileInfo(
            '固定测试账号',
            profileFixtureCover,
            signature: '完整登录态个人页',
          ),
        ),
        libraryRepositoryProvider.overrideWithValue(browsingLibrary ?? library),
        if (favoritesWindow != null)
          favoriteTrackWindowProvider.overrideWithValue(favoritesWindow),
        favoriteTracksProvider.overrideWith((ref) async* {
          if (favoritesWindow != null) {
            yield* ref.watch(favoriteTrackWindowProvider).stream;
            return;
          }
          yield fixture.tracks;
          yield* fixture.favorites.stream;
        }),
        playlistsProvider.overrideWith(
          (ref) => Stream.value([
            for (final id in [99, 100, 200, 300, 400])
              UserPlaylist(
                ownerId: 'netease:7001',
                id: 'ne:$id',
                name: '测试歌单 $id',
                description: '',
                coverAsset: profileFixtureCover,
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
          ]),
        ),
        neteaseAccountOverviewProvider.overrideWith(
          (ref) async => const NeteaseAccountOverview(
            {},
            NeteaseAccountLevel(9, {}),
            {},
            [],
          ),
        ),
        neteaseUnreadTotalProvider.overrideWith((ref) => 90),
        neteasePersonalStatsProvider.overrideWith((ref) async => personalStats),
        officialFootprintSourceProvider.overrideWithValue(
          footprintSource ?? _ProfileFootprintSource(),
        ),
        ...extraOverrides,
      ],
    );
    fixture = PersonalProfileFixture._(container, database, library, client);
    await container.read(platformAccountProvider.future);
    return fixture;
  }

  Future<void> dispose() async {
    container.dispose();
    await favorites.close();
    library.dispose();
    client.close();
    await database.close();
  }
}

/// Profile acceptance fixtures have no dependency on real footprint accounts.
/// The new summary reads only totalSeconds; other reports remain explicit.
class _ProfileFootprintSource implements OfficialFootprintSource {
  @override
  Future<int> totalSeconds() async => 5610 * 3600 + 120;
  @override
  Future<OfficialListenPeriod> currentWeek() =>
      Future.error(UnimplementedError());
  @override
  Future<OfficialListenPeriod> currentMonth() =>
      Future.error(UnimplementedError());
  @override
  Future<OfficialListenPeriod> history(String month) =>
      Future.error(UnimplementedError());
}
