import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesting_music/features/library/data/song_favorite_count.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/library/presentation/favorite_toggle_button.dart';
import 'package:mesting_music/shared/models/track.dart';

const _track = Track(
  id: 'netease_362937',
  title: '歌曲',
  artist: '歌手',
  album: '',
  duration: Duration.zero,
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.netease,
);
const _capture = bool.fromEnvironment('CAPTURE_HEART_BADGE');

void main() {
  setUpAll(() async {
    if (!_capture) return;
    await (FontLoader('Roboto')..addFont(
          File(
            'C:/Windows/Fonts/msyh.ttc',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });
  for (final dark in [true, false]) {
    for (final favorite in [false, true]) {
      testWidgets('播放器红心右上角计数不悬空、不越界 dark=$dark favorite=$favorite', (
        tester,
      ) async {
        for (final count in <int?>[5628000, 10000000, null, 0]) {
          await tester.pumpWidget(
            ProviderScope(
              key: ValueKey('$dark-$favorite-$count'),
              overrides: [
                favoriteTrackIdsProvider.overrideWithValue({
                  if (favorite) _track.id,
                }),
                songFavoriteCountProvider.overrideWith((ref, _) async => count),
              ],
              child: MaterialApp(
                theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
                home: Scaffold(
                  body: Center(
                    child: MediaQuery(
                      data: const MediaQueryData(
                        textScaler: TextScaler.linear(1.7),
                      ),
                      child: const FavoriteToggleButton(
                        track: _track,
                        player: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final button = find.byKey(
            const ValueKey('favorite-button-netease_362937'),
          );
          expect(tester.getSize(button), const Size(72, 48));
          expect(
            find.byIcon(
              favorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
            ),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.star_border_rounded), findsNothing);
          if (count != null) {
            final number = find.byKey(
              const ValueKey('song-favorite-count-netease_362937'),
            );
            final heart = find.byIcon(
              favorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
            );
            final numberRect = tester.getRect(number),
                heartRect = tester.getRect(heart);
            expect(numberRect.left, greaterThanOrEqualTo(heartRect.right - 1));
            expect(numberRect.center.dy, lessThan(heartRect.center.dy));
            expect(numberRect.bottom, greaterThan(heartRect.top));
            final buttonRect = tester.getRect(button);
            expect(numberRect.right, lessThanOrEqualTo(buttonRect.right));
            expect(numberRect.top, greaterThanOrEqualTo(buttonRect.top));
            expect(
              tester.widget<Text>(number).style?.color,
              favorite
                  ? favoriteFeedbackColor(tester.element(number))
                  : Theme.of(
                      tester.element(number),
                    ).colorScheme.onSurfaceVariant,
            );
          } else {
            expect(
              find.byKey(const ValueKey('song-favorite-count-netease_362937')),
              findsNothing,
            );
          }
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('红心计数视觉对照：未收藏、收藏、上限与缺失', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('heart-badge-proof'),
              child: Container(
                width: 360,
                color: const Color(0xFF252329),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final setting in [
                      (false, 5628000),
                      (true, 5628000),
                      (true, 10000000),
                      (false, null),
                    ])
                      ProviderScope(
                        overrides: [
                          favoriteTrackIdsProvider.overrideWithValue({
                            if (setting.$1) _track.id,
                          }),
                          songFavoriteCountProvider.overrideWith(
                            (ref, _) async => setting.$2,
                          ),
                        ],
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '我不难过',
                                      style: TextStyle(fontSize: 20),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      '孙燕姿',
                                      style: TextStyle(color: Colors.white60),
                                    ),
                                  ],
                                ),
                              ),
                              FavoriteToggleButton(track: _track, player: true),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (_capture) {
      await tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('heart-badge-proof')),
            )
            .toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../heart-count-ui-proof.png');
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
  });
}
