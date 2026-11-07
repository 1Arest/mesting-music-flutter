import '../../../shared/models/track.dart';
import '../data/platform_mv_repository.dart';
import 'netease_music_repository.dart';
import 'netease_media_uri.dart';

/// Reuses the complete MV page/controller/fullscreen transition. Only resource
/// lookup and its quality identifier differ between the two music platforms.
class NeteaseMvRepository extends PlatformMvRepository {
  const NeteaseMvRepository(super.api, this.music);
  final NeteaseMusicRepository music;
  @override
  Future<MusicMv?> lookup(Track track) async {
    if (track.source != TrackSource.netease) return null;
    final songs = await music.call('/song/detail', {
      'ids': [NeteaseMusicRepository.songId(track.id)],
    });
    final rows = NeteaseMusicRepository.rows(songs['songs']);
    final id = rows.isEmpty ? '0' : '${rows.first['mv'] ?? 0}';
    if ((int.tryParse(id) ?? 0) <= 0) return null;
    return byId(id, fallbackTitle: track.title);
  }

  Future<MusicMv?> byId(String id, {String fallbackTitle = ''}) async {
    NeteaseMusicRepository.songId(id);
    final detail = NeteaseMusicRepository.object(
      (await music.call('/mv/detail', {'id': id}))['data'],
    );
    final raw = detail['brs'];
    final resolutions = raw is Map
        ? raw.keys.map((e) => '$e')
        : NeteaseMusicRepository.rows(raw).map((e) => '${e['br']}');
    final qualities =
        resolutions
            .where((v) => (int.tryParse(v) ?? 0) > 0)
            .map((v) => MusicMvQuality('$id:$v', '${v}P'))
            .toList()
          ..sort(
            (a, b) => int.parse(
              b.hash.split(':').last,
            ).compareTo(int.parse(a.hash.split(':').last)),
          );
    if (qualities.isEmpty) return null;
    return MusicMv(
      id: id,
      title: '${detail['name'] ?? fallbackTitle}',
      qualities: qualities,
    );
  }

  @override
  Future<List<Uri>> urls(MusicMvQuality quality) async {
    final parts = quality.hash.split(':');
    if (parts.length != 2) return const [];
    final data = NeteaseMusicRepository.object(
      (await music.call('/mv/url', {
        'id': parts.first,
        'r': int.parse(parts.last),
      }))['data'],
    );
    final uri = neteaseMediaUri('${data['url'] ?? ''}');
    return uri != null &&
            uri.host.isNotEmpty &&
            {'http', 'https'}.contains(uri.scheme)
        ? [uri]
        : const [];
  }
}
