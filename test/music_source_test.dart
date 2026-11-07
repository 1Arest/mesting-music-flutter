import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/search/data/audius_music_source.dart';
import 'package:mesting_music/features/search/data/jamendo_music_source.dart';
import 'package:mesting_music/shared/models/track.dart';

void main() {
  group('AudiusMusicSource', () {
    test('解析可播放歌曲并过滤下架结果', () {
      final tracks = AudiusMusicSource.parseTracks({
        'data': [
          {
            'id': 'abc123',
            'title': 'Night Drive',
            'duration': 181,
            'genre': 'Electronic',
            'is_streamable': true,
            'is_unlisted': false,
            'permalink': 'https://audius.co/demo/night-drive',
            'user': {'name': 'Demo Artist', 'handle': 'demo'},
            'artwork': {'480x480': 'https://example.com/cover-480.jpg'},
          },
          {'id': 'blocked', 'title': 'Blocked', 'is_streamable': false},
          {'id': 'hidden', 'title': 'Hidden', 'is_unlisted': true},
        ],
      });

      expect(tracks, hasLength(1));
      expect(tracks.single.id, 'audius_abc123');
      expect(tracks.single.source, TrackSource.audius);
      expect(tracks.single.artist, 'Demo Artist');
      expect(tracks.single.duration, const Duration(seconds: 181));
      expect(tracks.single.audioAsset, contains('/tracks/abc123/stream'));
      expect(tracks.single.coverAsset, 'https://example.com/cover-480.jpg');
    });
  });

  group('JamendoMusicSource', () {
    test('解析包含授权信息的歌曲', () {
      final tracks = JamendoMusicSource.parseTracks({
        'results': [
          {
            'id': '42',
            'name': 'Open Song',
            'artist_name': 'Open Artist',
            'album_name': 'Open Album',
            'duration': '210',
            'audio': 'https://example.com/audio.mp3',
            'image': 'https://example.com/image.jpg',
            'shareurl': 'https://jamendo.com/track/42',
            'license_ccurl': 'https://creativecommons.org/licenses/by/4.0/',
          },
        ],
      });

      expect(tracks, hasLength(1));
      expect(tracks.single.id, 'jamendo_42');
      expect(tracks.single.source, TrackSource.jamendo);
      expect(tracks.single.licenseUrl, contains('creativecommons.org'));
    });
  });
}
