import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/models/track.dart';

import 'support/test_tracks.dart';

void main() {
  test('Track 数据快照可以完整往返', () {
    for (final track in testTracks) {
      final restored = Track.fromJson(track.toJson());
      expect(restored.id, track.id);
      expect(restored.title, track.title);
      expect(restored.artist, track.artist);
      expect(restored.album, track.album);
      expect(restored.duration, track.duration);
      expect(restored.audioAsset, track.audioAsset);
      expect(restored.coverAsset, track.coverAsset);
      expect(restored.lyricsAsset, track.lyricsAsset);
      expect(restored.source, track.source);
      expect(restored.provider, track.provider);
      expect(restored.isPreview, track.isPreview);
      expect(restored.externalUrl, track.externalUrl);
      expect(restored.licenseUrl, track.licenseUrl);
    }
  });

  test('在线歌曲数据快照可以完整往返', () {
    const track = Track(
      id: 'audius_test',
      title: 'Online song',
      artist: 'Artist',
      album: 'Album',
      duration: Duration(seconds: 123),
      audioAsset: 'https://example.com/stream',
      coverAsset: 'https://example.com/cover.jpg',
      lyricsAsset: '',
      source: TrackSource.audius,
      provider: 'Audius',
      externalUrl: 'https://audius.co/example',
      licenseUrl: 'https://example.com/license',
    );

    final restored = Track.fromJson(track.toJson());
    expect(restored.toJson(), track.toJson());
    expect(restored.isRemote, isTrue);
    expect(restored.hasLyrics, isFalse);
  });

  test('旧版酷狗歌曲快照会自动补回公开歌词入口', () {
    const legacyTrack = Track(
      id: 'kugou_aef0740270fe89918f07807c8d669fb7',
      title: '虚拟',
      artist: '陈粒',
      album: '小梦大半',
      duration: Duration(milliseconds: 240779),
      audioAsset: 'https://example.com/song.mp3',
      coverAsset: 'https://example.com/cover.jpg',
      lyricsAsset: '',
      source: TrackSource.kugou,
      provider: '酷狗概念版',
    );

    expect(legacyTrack.hasLyrics, isTrue);
    expect(
      legacyTrack.resolvedLyricsAsset,
      startsWith('mesting-lyrics://kugou/'),
    );
    expect(
      Uri.parse(legacyTrack.resolvedLyricsAsset).queryParameters['durationMs'],
      '240779',
    );
    expect(
      legacyTrack.toJson()['lyricsAsset'],
      legacyTrack.resolvedLyricsAsset,
    );
  });

  test('通知媒体信息使用准备好的本地封面 URI', () {
    final artworkUri = Uri.file('C:/cache/notification_artwork/demo.jpg');
    final mediaItem = testTracks.first.toMediaItem(artUri: artworkUri);

    expect(mediaItem.artUri, artworkUri);
    expect(mediaItem.extras?['coverAsset'], testTracks.first.coverAsset);
  });

  test('在线歌曲通知媒体信息直接使用远程封面', () {
    const track = Track(
      id: 'remote_artwork',
      title: 'Online song',
      artist: 'Artist',
      album: 'Album',
      duration: Duration(seconds: 123),
      audioAsset: 'https://example.com/stream',
      coverAsset: 'https://example.com/cover.jpg',
      lyricsAsset: '',
      source: TrackSource.audius,
    );

    expect(track.toMediaItem().artUri, Uri.parse(track.coverAsset));
  });
}
