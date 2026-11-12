import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/search/data/fused_song_search.dart';
import 'package:mesting_music/shared/models/song_search_facts.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'search184_fusion_test.dart' show song;
import 'search185_originals_test.dart' show api;
import 'package:mesting_music/features/music_platform/data/platform_search_repository.dart';

class _Source extends PlatformSearchRepository {
  _Source(this.result, this.permission) : super(api());
  final PlatformSearchPage result;
  final SearchPlaybackAccess permission;
  final checked = <String>[];
  @override
  Future<PlatformSearchPage> search(
    String query, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async => result;
  @override
  Future<SongSearchFacts> inspectAvailability(
    Track track,
    SongSearchFacts facts, {
    Future<void>? abortTrigger,
  }) async {
    checked.add(track.id);
    return facts.withAccess(permission);
  }
}

void main() {
  test(
    'unknown access labels omit empty separators and preserve work evidence',
    () {
      const raw = SongSearchFacts(
        kind: SearchRecordingKind.cover,
        originalWorkId: '701',
        originalTitle: '远方的海岸',
        originalAlbum: '作品集甲',
        originalArtists: ['创作者甲'],
      );
      expect(raw.label, '翻唱');
      expect(
        const SongSearchFacts(workRelation: SearchWorkRelation.original).label,
        '原唱',
      );
      expect(const SongSearchFacts().label, '');
      final full = raw
          .withWork(SearchWorkRelation.version)
          .withAccess(SearchPlaybackAccess.full);
      expect(full.label, '翻唱 · 完整版');
      expect(full.originalWorkId, raw.originalWorkId);
      expect(full.originalTitle, raw.originalTitle);
      expect(full.originalAlbum, raw.originalAlbum);
      expect(full.originalArtists, raw.originalArtists);
      expect(full.workRelation, SearchWorkRelation.version);
    },
  );
  // Same regression with unrelated synthetic names proves that the rule is not
  // a special-case song/singer table. Catalogue "original" flags are deliberate.
  for (final sample in [('晴天', '周杰伦', '186016'), ('远方的海岸', '创作者甲', '701')]) {
    test(
      'target work precedes unrelated original compositions: ${sample.$1}',
      () async {
        final title = sample.$1, artist = sample.$2, id = sample.$3;
        final n = song(
          'netease_$id',
          TrackSource.netease,
          title: title,
          artist: artist,
        );
        final k = song(
          'kugou_target',
          TrackSource.kugou,
          title: title,
          artist: artist,
        );
        final cover = song(
          'netease_cover',
          TrackSource.netease,
          title: '$title (翻唱版)',
          artist: '演唱者乙',
        );
        final unrelated = [
          for (var i = 0; i < 8; i++)
            song(
              'netease_other$i',
              TrackSource.netease,
              title: title,
              artist: '同名创作者$i',
            ),
        ];
        final primary = _Source(
          PlatformSearchPage(
            [...unrelated, cover, n],
            10,
            false,
            facts: {
              for (final t in unrelated)
                t.id: const SongSearchFacts(
                  kind: SearchRecordingKind.original,
                  access: SearchPlaybackAccess.full,
                ),
              n.id: const SongSearchFacts(
                kind: SearchRecordingKind.original,
                membership: true,
              ),
              cover.id: SongSearchFacts(
                kind: SearchRecordingKind.cover,
                originalTitle: title,
                originalArtists: [artist],
                originalWorkId: id,
              ),
            },
          ),
          SearchPlaybackAccess.preview,
        );
        final secondary = _Source(
          PlatformSearchPage([k], 1, false),
          SearchPlaybackAccess.full,
        );
        final result =
            await FusedSongSearchRepository(
                  api(),
                  primary: primary,
                  secondary: () async => secondary,
                  primaryLabel: '网易云',
                  secondaryLabel: '酷狗',
                ).search(title)
                as FusedSongSearchPage;
        expect(result.tracks.first.id, k.id);
        expect(result.sources[k.id]!.map((t) => t.id), [k.id, n.id]);
        expect(result.facts[k.id]!.label, '原唱 · 完整版');
        expect(result.facts[n.id]!.label, '原唱 · 试听');
        expect(result.tracks[1].id, cover.id);
        expect(
          result.tracks.skip(2).map((t) => t.id),
          unrelated.map((t) => t.id),
        );
        for (final t in unrelated) {
          expect(result.facts[t.id]!.label, isNot(contains('原唱')));
          expect(result.facts[t.id]!.workRelation, SearchWorkRelation.other);
        }
        expect(
          primary.checked,
          [n.id],
          reason: 'Unrelated originals cannot consume the permission budget',
        );
        expect(secondary.checked, [k.id]);
      },
    );
  }
  test(
    'ambiguous links and catalogue original flags do not invent an original',
    () {
      final a = song('netease_a', TrackSource.netease, artist: '甲');
      final b = song('netease_b', TrackSource.netease, artist: '乙');
      final result = groupSongSearchResults(
        [a, b],
        [],
        hasMore: false,
        query: '晴天',
        facts: {
          a.id: const SongSearchFacts(
            kind: SearchRecordingKind.original,
            originalTitle: '晴天',
            originalArtists: ['甲'],
          ),
          b.id: const SongSearchFacts(
            kind: SearchRecordingKind.original,
            originalTitle: '晴天',
            originalArtists: ['乙'],
          ),
        },
      );
      expect(result.facts.values.every((f) => !f.label.contains('原唱')), isTrue);
      final explicit = groupSongSearchResults(
        [a, b],
        [],
        hasMore: false,
        query: '晴天 乙',
        facts: result.facts,
      );
      expect(explicit.tracks.first, b);
      expect(explicit.facts[b.id]!.workRelation, SearchWorkRelation.original);
    },
  );
  test(
    'unknown catalogue records keep platform ranking without false authorship',
    () {
      final tracks = [
        song('netease_a', TrackSource.netease, artist: '甲'),
        song('netease_b', TrackSource.netease, artist: '乙'),
      ];
      final result = groupSongSearchResults(
        tracks,
        [],
        hasMore: false,
        query: '晴天',
        facts: {
          for (final t in tracks)
            t.id: const SongSearchFacts(kind: SearchRecordingKind.original),
        },
      );
      expect(result.tracks, tracks);
      expect(
        result.facts.values.every(
          (f) =>
              f.workRelation == SearchWorkRelation.unknown &&
              !f.label.contains('原唱'),
        ),
        isTrue,
      );
    },
  );
}
