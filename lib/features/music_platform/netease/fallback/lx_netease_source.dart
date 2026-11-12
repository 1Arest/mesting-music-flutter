import 'package:http/http.dart' as http;
import '../../../../shared/models/track.dart';
import 'lx_script_engine.dart';
import 'lx_source_catalog.dart';
import 'lx_anonymous_transport.dart';
import 'netease_fallback_source.dart';
import 'netease_source_transport.dart';

/// Only the original NetEase ID enters the LX wy resolver. It never creates a
/// second catalogue identity or changes likes/comments/history associations.
class LxNeteaseSource implements NeteaseExactIdSource {
  LxNeteaseSource(
    this.source,
    this.client, {
    required this.pool,
    LxEngineFactory? engineFactory,
  }) : engineFactory = engineFactory ?? WebViewLxScriptEngine.new;
  final LxMusicSource source;
  final http.Client client;
  final LxEnginePool pool;
  final LxEngineFactory engineFactory;
  @override
  String get label => source.adapter;
  @override
  Future<List<Track>> search(Track original) async => [original];
  bool get _current =>
      client is! NeteaseSourceClient ||
      !(client as NeteaseSourceClient).isClosed;

  @override
  Future<Track?> resolve(Track candidate) => pool.run(() async {
    final id = candidate.id.startsWith('netease_')
        ? candidate.id.substring(8)
        : candidate.platformSongId;
    if (!RegExp(r'^\d{1,20}$').hasMatch(id)) {
      throw const NeteaseSourceFailure('wrong_song_id');
    }
    final requested = switch (candidate.playbackQuality) {
      'flac' => 'flac',
      'high' => 'flac24bit',
      '320' => '320k',
      _ => '128k',
    };
    final engine = engineFactory(client);
    try {
      final url = await engine.resolve(source, {
        'id': id,
        'songmid': id,
        'songId': id,
        'source': 'wy',
        'name': candidate.title,
        'songname': candidate.title,
        'singer': candidate.artist,
        'artist': candidate.artist,
        'albumName': candidate.album,
        'interval':
            '${candidate.duration.inSeconds ~/ 60}:${(candidate.duration.inSeconds % 60).toString().padLeft(2, '0')}',
      }, requested);
      final uri = Uri.tryParse(url);
      if (!_current || uri == null || !LxAnonymousTransport.publicUri(uri)) {
        return null;
      }
      // Leave quality unknown here. The shared media probe measures the actual
      // file; a script's requested FLAC/Hi-Res tier is never accepted as proof.
      return candidate.copyWith(
        audioAsset: url,
        audioHeaders: const {},
        audioBitrate: 0,
        playbackQuality: '',
        isPreview: false,
      );
    } finally {
      engine.dispose();
    }
  }, () => _current);
}
