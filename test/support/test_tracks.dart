import 'package:mesting_music/shared/models/track.dart';

const testTracks = <Track>[
  Track(
    id: 'test_track_one',
    title: 'Test Track One',
    artist: 'Test Artist',
    album: 'Test Album',
    duration: Duration(minutes: 3, seconds: 12),
    audioAsset: 'test/audio/one.mp3',
    coverAsset: 'assets/images/theme_gallery/shinchan-avatar-v2.png',
    lyricsAsset: '',
  ),
  Track(
    id: 'test_track_two',
    title: 'Test Track Two',
    artist: 'Test Artist',
    album: 'Test Album',
    duration: Duration(minutes: 4, seconds: 8),
    audioAsset: 'test/audio/two.mp3',
    coverAsset: 'assets/images/theme_gallery/shinchan-avatar-v2.png',
    lyricsAsset: '',
  ),
  Track(
    id: 'test_track_three',
    title: 'Test Track Three',
    artist: 'Another Artist',
    album: 'Another Album',
    duration: Duration(minutes: 2, seconds: 45),
    audioAsset: 'test/audio/three.mp3',
    coverAsset: 'assets/images/theme_gallery/shinchan-avatar-v2.png',
    lyricsAsset: '',
  ),
  Track(
    id: 'test_track_four',
    title: 'Test Track Four',
    artist: 'Another Artist',
    album: 'Another Album',
    duration: Duration(minutes: 3, seconds: 28),
    audioAsset: 'test/audio/four.mp3',
    coverAsset: 'assets/images/theme_gallery/shinchan-avatar-v2.png',
    lyricsAsset: '',
  ),
];
