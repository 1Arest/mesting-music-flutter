import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/data/linked_music_recordings.dart';
import 'package:mesting_music/features/music_platform/data/linked_music_mvs.dart';
import 'package:mesting_music/features/music_platform/data/platform_mv_repository.dart';
import 'package:mesting_music/features/music_platform/data/platform_search_repository.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'search184_fusion_test.dart' show song;
import 'search185_originals_test.dart' show api;

class _Search extends PlatformSearchRepository {
  _Search(this.tracks) : super(api());
  final List<Track> tracks;
  Completer<PlatformSearchPage>? pending;
  @override
  Future<PlatformSearchPage> search(
    String q, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async =>
      pending?.future ??
      Future.value(PlatformSearchPage(tracks, tracks.length, false));
}

class _Videos extends PlatformMvRepository {
  _Videos(this.video) : super(api());
  final MusicMv? video;
  @override
  Future<MusicMv?> lookup(Track track) async => video;
}

MusicMv mv(
  TrackSource source, {
  String title = '晴天',
  String artist = '周杰伦',
  int seconds = 270,
}) => MusicMv(
  id: source.name,
  title: title,
  artist: artist,
  duration: Duration(seconds: seconds),
  source: source,
  qualities: [MusicMvQuality('${source.name}-video', '高清')],
);
void main() {
  final n = song('netease_701', TrackSource.netease),
      k = song('kugou_hash', TrackSource.kugou);
  test(
    'actual transport reconstructs the foreign identity without borrowing a NetEase numeric ID',
    () async {
      final resolved = n.copyWith(
        platformSongId: 'NE-only-id',
        audioOrigin: const AudioOrigin(AudioOrigin.kugou, 'kugou_real_hash'),
      );
      final actual = actualSourceRecording(resolved)!;
      expect(actual.source, TrackSource.kugou);
      expect(actual.id, 'kugou_real_hash');
      expect(actual.platformSongId, '');
      expect(actual.audioAsset, '');
      expect(actual.audioHeaders, isEmpty);
      var searches = 0;
      final linked = await linkMusicRecordings(resolved, (_) async {
        searches++;
        return _Search([]);
      });
      expect(linked.recordings.map((t) => t.source), [
        TrackSource.kugou,
        TrackSource.netease,
      ]);
      expect(searches, 0);
    },
  );
  test(
    'same-title covers and unknown durations cannot bind another platform comment pool',
    () async {
      final cover = song('kugou_cover', TrackSource.kugou, artist: '其他歌手');
      final unknown = song('kugou_unknown', TrackSource.kugou, seconds: 0);
      final linked = await linkMusicRecordings(
        n,
        (_) async => _Search([cover, unknown, k]),
      );
      expect(linked.recordings.map((t) => t.id), [n.id, k.id]);
    },
  );
  test(
    'MV equality preserves performer and version instead of matching titles alone',
    () {
      expect(
        sameMusicMv(
          mv(TrackSource.netease),
          mv(TrackSource.kugou, seconds: 272),
        ),
        true,
      );
      expect(
        sameMusicMv(
          mv(TrackSource.netease),
          mv(TrackSource.kugou, title: '晴天 (Live)'),
        ),
        false,
      );
      expect(
        sameMusicMv(
          mv(TrackSource.netease),
          mv(TrackSource.kugou, artist: '其他歌手'),
        ),
        false,
      );
      expect(
        sameMusicMv(mv(TrackSource.netease), mv(TrackSource.kugou, seconds: 0)),
        false,
      );
    },
  );
  test(
    'primary MV is published before a slow other source; counterpart has its own video ID',
    () async {
      final pending = Completer<PlatformSearchPage>(),
          other = _Search([])..pending = pending;
      final iterator = StreamIterator(
        discoverLinkedMusicMvs(
          n,
          repositories: (source) async => MvSourceRepositories(
            _Videos(mv(source)),
            source == TrackSource.kugou ? other : _Search([]),
            () => true,
          ),
        ),
      );
      expect(await iterator.moveNext(), true);
      expect(iterator.current.choices.single.mv.id, 'netease');
      expect(iterator.current.discovering, true);
      final next = iterator.moveNext();
      pending.complete(PlatformSearchPage([k], 1, false));
      expect(await next, true);
      expect(iterator.current.choices.map((c) => c.mv.id), [
        'netease',
        'kugou',
      ]);
      expect(iterator.current.discovering, false);
      await iterator.cancel();
    },
  );
  test(
    'a missing primary MV can use the other source of the verified recording',
    () async {
      final values = await discoverLinkedMusicMvs(
        n,
        repositories: (source) async => MvSourceRepositories(
          _Videos(source == TrackSource.netease ? null : mv(source)),
          _Search([k]),
          () => true,
        ),
      ).toList();
      expect(values.last.choices.single.source, TrackSource.kugou);
    },
  );
}
