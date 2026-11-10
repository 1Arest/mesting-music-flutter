import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/data/platform_search_repository.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/shared/models/song_search_facts.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'search184_fusion_test.dart' show song;

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:18500');
}

class _ProbeApi extends MusicPlatformApi {
  _ProbeApi(this.row)
    : super(
        server: _Server(),
        client: MockClient((_) async => throw StateError('No media IO')),
      );
  final Map<String, dynamic> row;
  final paths = <String>[];
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String> query = const {},
    bool allowBusinessError = false,
    Future<void>? abortTrigger,
    PlatformSession? expectedSession,
  }) async {
    paths.add(path);
    expect(query, {'hash': 'hash', 'quality': '128'});
    expect(allowBusinessError, true);
    return {'data': row};
  }
}

class _Access extends NeteaseMusicRepository {
  _Access(this.row)
    : super(
        NeteaseApi(
          MockClient((_) async => throw StateError('No media requests')),
        )..configure(
          const NeteaseSession(
            userId: 'synthetic',
            deviceId: 'fixture',
            cookies: {'MUSIC_U': 'test-only'},
          ),
        ),
      );
  final Map<String, dynamic> row;
  @override
  Future<Map<String, dynamic>> call(
    String route, [
    Map<String, Object?> query = const {},
    Future<void>? abort,
  ]) async {
    expect(route, '/song/url');
    expect(query['level'], 'standard');
    return {
      'data': [row],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const f = SongSearchFacts(
    kind: SearchRecordingKind.original,
    membership: true,
  );
  final n = song('netease_1', TrackSource.netease);
  test(
    'actual full/trial metadata, not member/freeTrialPrivilege flags, selects access',
    () async {
      final full = await _Access({
        'url': 'https://media.example/full.mp3',
        'time': 269000,
        'freeTrialPrivilege': {'resConsumable': true},
      }).inspectSearchAvailability(n, f);
      expect(full.access, SearchPlaybackAccess.full);
      expect(full.membership, true);
      expect(
        (await _Access({
          'url': 'https://media.example/part.mp3',
          'time': 30000,
        }).inspectSearchAvailability(n, f)).access,
        SearchPlaybackAccess.preview,
      );
      expect(
        (await _Access({
          'url': 'https://media.example/part.mp3',
          'freeTrialInfo': {},
        }).inspectSearchAvailability(n, f)).access,
        SearchPlaybackAccess.preview,
      );
      expect(
        (await _Access({'url': null}).inspectSearchAvailability(n, f)).access,
        SearchPlaybackAccess.restricted,
      );
      expect(
        (await _Access({
          'url': 'https://media.example/unknown.mp3',
        }).inspectSearchAvailability(n, f)).access,
        SearchPlaybackAccess.unknown,
      );
    },
  );
  test(
    'Kugou probes only URL metadata and leaves registration errors unknown',
    () async {
      for (final (row, access) in [
        (
          {'url': 'https://media.example/full.mp3', 'timelength': 269000},
          SearchPlaybackAccess.full,
        ),
        (
          {'url': 'https://media.example/part.mp3', 'timelength': 30000},
          SearchPlaybackAccess.preview,
        ),
        (
          {'url': 'https://media.example/unknown.mp3'},
          SearchPlaybackAccess.unknown,
        ),
        ({'errcode': 20028}, SearchPlaybackAccess.unknown),
        ({'priv_status': 0}, SearchPlaybackAccess.restricted),
      ]) {
        final api = _ProbeApi(row);
        final result = await PlatformSearchRepository(
          api,
        ).inspectAvailability(song('kugou_HASH', TrackSource.kugou), f);
        expect(result.access, access);
        expect(api.paths, ['/song/url']);
      }
    },
  );
}
