import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/utils/media_uri.dart';

void main() {
  // Representative public NetEase imageView chains use ordered duplicate
  // keys and an encoded pipe. Map round-trips change the server operation.
  const chain =
      'thumbnail=500y500&type=webp&imageView&image=watermark%7C1'
      '&dx=8&dy=8&thumbnail=100y100&type=png&image=second&dx=2&dy=2';
  test(
    'ordered cover processing survives HTTPS upgrade and thumbnail request',
    () {
      const original = 'http://p1.music.126.net/a==/cover.jpg?$chain';
      final resized = sizedArtworkUri(original, width: 192, height: 192);
      expect(resized, 'https://p1.music.126.net/a==/cover.jpg?$chain');
      expect(Uri.parse(resized).queryParametersAll['thumbnail'], [
        '500y500',
        '100y100',
      ]);
      expect(artworkRequestHeaders(resized), {
        'User-Agent': 'MestingMusic/1.0 (Artwork)',
      });
    },
  );
  test(
    'different ordered chains never share rejection or retained-frame identity',
    () {
      const a = 'https://p1.music.126.net/a.jpg?image=one&image=two';
      const b = 'https://p1.music.126.net/a.jpg?image=two';
      const c = 'https://p2.music.126.net/a.jpg?image=one&image=two';
      expect(artworkContentIdentity(a), isNot(artworkContentIdentity(b)));
      expect(artworkContentIdentity(a), artworkContentIdentity(c));
      const signed = 'https://p1.music.126.net/a.jpg?token=Ab%2Bcd&expires=123';
      expect(sizedArtworkUri(signed), signed);
      expect(
        artworkContentIdentity('$a&token=A'),
        artworkContentIdentity('$a&token=B'),
      );
      expect(
        artworkContentIdentity(
          'https://p1.music.126.net/a.jpg?param=192y192&token=A',
        ),
        artworkContentIdentity(
          'https://p1.music.126.net/a.jpg?param=768y768&token=B',
        ),
      );
      const repeated = 'https://p1.music.126.net/a.jpg?param=1y1&param=2y2';
      expect(sizedArtworkUri(repeated), repeated);
    },
  );
  test(
    'bare and simple-param photos keep bounded requests and shared identity',
    () {
      const bare = 'http://p1.music.126.net/a.jpg';
      final small = sizedArtworkUri(bare, width: 192, height: 192);
      final large = sizedArtworkUri(small, width: 9000, height: 1);
      expect(small, 'https://p1.music.126.net/a.jpg?param=192y192');
      expect(large, 'https://p1.music.126.net/a.jpg?param=1024y32');
      expect(artworkContentIdentity(small), artworkContentIdentity(large));
      const other = 'https://other.example/a.jpg?image=one&image=two';
      expect(sizedArtworkUri(other), other);
    },
  );
}
