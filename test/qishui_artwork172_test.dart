import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_models.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/shared/widgets/track_artwork.dart';
import 'qishui_recovery172_test.dart' show song172;

void main() {
  test('empty preferred image does not hide a valid album cover', () {
    final track = sodaTrack({
      'id': 'fixture',
      'name': 'fixture',
      'duration': 180000,
      'url_cover': '',
      'cover_url': {
        'urls': ['', 'https://images.example/cover.jpg'],
      },
      'album': {'url_cover': 'https://images.example/album.jpg'},
    })!;
    expect(track.coverAsset, 'https://images.example/cover.jpg');
    expect(track.coverAlternatives, ['https://images.example/album.jpg']);
    expect(
      Track.fromJson(track.toJson()).coverAlternatives,
      track.coverAlternatives,
    );
    expect(
      track.copyWith(audioAsset: 'file:///fixture/audio').coverAlternatives,
      track.coverAlternatives,
    );
    expect(
      track.toMediaItem().extras?['coverAlternatives'],
      track.coverAlternatives,
    );
  });
  test('each valid CDN base gets its own URI/template image', () {
    expect(
      sodaPictures({
        'urls': ['', 'https://cdn.example/img/', 'https://backup.example/img/'],
        'uri': 'tos-cn/cover-id',
        'template_prefix': 'tplv-luna',
      }),
      [
        'https://cdn.example/img/tos-cn/cover-id~tplv-luna-resize:960:960.png',
        'https://backup.example/img/tos-cn/cover-id~tplv-luna-resize:960:960.png',
      ],
    );
  });
  test('complete signed URLs are preserved and list failures fall through', () {
    expect(
      sodaPicture({
        'urls': [
          '',
          'file:///wrong',
          'https://cdn.example/c.jpg?x=1&sign=fixture',
        ],
      }),
      'https://cdn.example/c.jpg?x=1&sign=fixture',
    );
    expect(sodaPicture('//cdn.example/c.jpg'), 'https://cdn.example/c.jpg');
    expect(
      sodaPicture('http://cdn.example/c.jpg'),
      'https://cdn.example/c.jpg',
    );
  });
  for (final value in [
    'file:///image',
    'https://private:secret@images.example/c.jpg',
    'javascript:alert(1)',
    'https://',
  ]) {
    test(
      'invalid or credential-bearing picture is rejected: $value',
      () => expect(sodaPicture(value), ''),
    );
  }
  test('an unassembled base or traversal is never shown as an image', () {
    expect(
      sodaPicture({
        'urls': ['https://cdn.example/img/'],
      }),
      '',
    );
    expect(
      sodaPicture({
        'urls': ['https://cdn.example/img/'],
        'uri': '../wrong',
      }),
      '',
    );
  });
  test('playlist image aliases also fall through empty values', () {
    final playlist = QishuiPlaylist.parse({
      'playlist_id': 'fixture',
      'name': 'fixture',
      'url_cover': '',
      'cover_url': '',
      'style': {
        'cover_url_list': ['https://cdn.example/list.jpg'],
      },
    }).single;
    expect(playlist.cover, 'https://cdn.example/list.jpg');
  });
  testWidgets('a failed song picture moves to its supplied backup once', (
    tester,
  ) async {
    const backup = 'assets/images/playlists/13416469337261709.jpeg';
    final track = song172(0).copyWith(
      coverAsset: 'assets/missing-fixture172.png',
      coverAlternatives: [backup],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TrackArtwork(track: track, width: 48, height: 48),
          ),
        ),
      ),
    );
    // Inject the terminal failure at Flutter Image's public error boundary;
    // this verifies the ArtworkImage -> TrackArtwork hand-off without real IO.
    final image = tester.widget<Image>(find.byType(Image).first);
    image.errorBuilder!(
      tester.element(find.byType(Image).first),
      const FormatException('fixture decode'),
      null,
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<ArtworkImage>(find.byType(ArtworkImage)).uri, backup);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
