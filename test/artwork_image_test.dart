import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/shared/widgets/retained_artwork_frame.dart';

void main() {
  test('legacy packaged artwork paths resolve to optimized assets', () {
    expect(
      canonicalArtworkUri('assets/branding/dress-midnight-launch.png'),
      'assets/branding/dress-midnight-launch-v2.webp',
    );
    expect(
      canonicalArtworkUri('assets/images/themes/shinchan_progress.png'),
      'assets/images/theme_gallery/shinchan-avatar-v2.png',
    );
    expect(
      canonicalArtworkUri('https://cdn.example/cover.png'),
      'https://cdn.example/cover.png',
    );
  });

  testWidgets('artwork decode dimensions follow rendered physical size', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 3),
        child: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(artworkCacheDimension(context, 48), 144);
    expect(artworkCacheDimension(context, 1000), 2048);
    expect(artworkCacheDimension(context, null), isNull);
  });

  testWidgets(
    'signed avatar URL refresh keeps the same gapless image element',
    (tester) async {
      Widget app(String uri) {
        return MaterialApp(
          home: ArtworkImage(
            uri: uri,
            width: 72,
            height: 72,
            retryOnNetworkError: true,
          ),
        );
      }

      await tester.pumpWidget(app('https://cdn.example/avatar?token=first'));
      final first = tester.widget<RetainedArtworkFrame>(
        find.byType(RetainedArtworkFrame),
      );

      await tester.pumpWidget(app('https://cdn.example/avatar?token=second'));
      final second = tester.widget<RetainedArtworkFrame>(
        find.byType(RetainedArtworkFrame),
      );

      expect(first.key, second.key);
      expect(second.image, isNotNull);
    },
  );

  testWidgets('decode dimensions can be smaller than the layout dimensions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(devicePixelRatio: 3),
        child: MaterialApp(
          home: ArtworkImage(
            uri: 'assets/example.png',
            width: double.infinity,
            height: 180,
            decodeWidth: 120,
            decodeHeight: 180,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as ResizeImage;
    expect(provider.width, 360);
    expect(provider.height, 540);
  });

  testWidgets('single-axis decode preserves the original aspect ratio', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(devicePixelRatio: 3),
        child: MaterialApp(
          home: ArtworkImage(
            uri: 'assets/example.png',
            width: 240,
            height: 360,
            decodeWidth: 240,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as ResizeImage;
    expect(provider.width, 720);
    expect(provider.height, isNull);
    expect(image.fit, BoxFit.contain);
  });
}
