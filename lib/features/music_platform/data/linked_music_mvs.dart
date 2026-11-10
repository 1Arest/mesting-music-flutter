import '../../../shared/models/track.dart';
import '../../search/data/song_search_ranking.dart' show searchText;
import '../../search/data/fused_song_search.dart' show sameSearchRecording;
import '../netease/netease_mv_repository.dart';
import 'linked_music_recordings.dart';
import 'platform_mv_repository.dart';
import 'platform_search_repository.dart';

class MvSourceRepositories {
  const MvSourceRepositories(this.videos, this.songs, this.current);
  final PlatformMvRepository videos;
  final PlatformSearchRepository songs;
  final bool Function() current;
}

class LinkedMvChoice {
  const LinkedMvChoice(this.track, this.mv, this.repository, this.current);
  final Track track;
  final MusicMv mv;
  final PlatformMvRepository repository;
  final bool Function() current;
  TrackSource get source => track.source;
}

class LinkedMusicMvs {
  const LinkedMusicMvs(
    this.choices, {
    this.discovering = false,
    this.warnings = const [],
  });
  final List<LinkedMvChoice> choices;
  final bool discovering;
  final List<String> warnings;
}

String _mvTitle(String value) => searchText(
  value,
).replaceAll(RegExp(r'\((?:官方版|官方mv|高清|超清|officialmv|hd)\)$'), '');
String _mvArtist(String value) {
  final parts =
      value
          .split(RegExp(r'[/、&,，]'))
          .map(searchText)
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return parts.join('/');
}

bool sameMusicMv(MusicMv a, MusicMv b) =>
    a.duration > Duration.zero &&
    b.duration > Duration.zero &&
    _mvTitle(a.title) == _mvTitle(b.title) &&
    _mvArtist(a.artist).isNotEmpty &&
    _mvArtist(a.artist) == _mvArtist(b.artist) &&
    (a.duration.inMilliseconds - b.duration.inMilliseconds).abs() <= 3000;

/// Yield the primary MV immediately. A slow or unavailable other platform must
/// not delay the first video. Counterparts come from exact song associations and
/// MV metadata, never a title-only video guess or a reused song comment ID.
Stream<LinkedMusicMvs> discoverLinkedMusicMvs(
  Track track, {
  String? mvId,
  required Future<MvSourceRepositories> Function(TrackSource) repositories,
  bool Function()? isCurrent,
}) async* {
  final seed = actualSourceRecording(track) ?? track;
  if (![TrackSource.kugou, TrackSource.netease].contains(seed.source)) {
    yield const LinkedMusicMvs([]);
    return;
  }
  bool current() => isCurrent?.call() ?? true;
  if (!current()) return;
  final choices = <LinkedMvChoice>[];
  final warnings = <String>[];
  MusicMv? primary;
  try {
    final source = await repositories(
      seed.source,
    ).timeout(const Duration(seconds: 6));
    if (!current()) return;
    primary = mvId != null && source.videos is NeteaseMvRepository
        ? await (source.videos as NeteaseMvRepository).byId(
            mvId,
            fallbackTitle: seed.title,
            fallbackArtist: seed.artist,
          )
        : await source.videos.lookup(seed);
    if (!current() || !source.current()) return;
    if (primary != null) {
      choices.add(LinkedMvChoice(seed, primary, source.videos, source.current));
    }
  } on Object {
    warnings.add('当前来源MV暂时无法加载');
  }
  yield LinkedMusicMvs(
    List.unmodifiable(choices),
    discovering: true,
    warnings: List.unmodifiable(warnings),
  );
  if (!current()) return;
  final other = seed.source == TrackSource.kugou
      ? TrackSource.netease
      : TrackSource.kugou;
  try {
    final source = await repositories(
      other,
    ).timeout(const Duration(seconds: 6));
    if (!current()) return;
    final title = primary?.title ?? seed.title,
        artist = primary?.artist.isNotEmpty == true
            ? primary!.artist
            : seed.artist;
    if (artist.isNotEmpty) {
      final page = await source.songs
          .search('$title $artist')
          .timeout(const Duration(seconds: 12));
      if (!current()) return;
      final matching = page.tracks
          .where(
            (t) =>
                _mvTitle(t.title) == _mvTitle(title) &&
                _mvArtist(t.artist) == _mvArtist(artist),
          )
          .take(2);
      for (final candidate in matching) {
        if (!current() || !source.current()) return;
        final mv = await source.videos
            .lookup(candidate)
            .timeout(const Duration(seconds: 12));
        if (!current() || !source.current()) return;
        if (mv == null) continue;
        final verified = primary != null
            ? sameMusicMv(primary, mv)
            : sameSearchRecording(seed, candidate) &&
                  _mvTitle(mv.title) == _mvTitle(seed.title) &&
                  _mvArtist(mv.artist) == _mvArtist(seed.artist);
        if (verified) {
          choices.add(
            LinkedMvChoice(candidate, mv, source.videos, source.current),
          );
          break;
        }
      }
    }
  } on Object {
    warnings.add('另一平台MV核对未完成，可重试');
  }
  yield LinkedMusicMvs(
    List.unmodifiable(choices),
    warnings: List.unmodifiable(warnings),
  );
}
