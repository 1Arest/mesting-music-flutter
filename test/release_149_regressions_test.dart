import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/cache/browse_response_cache.dart';
import 'package:mesting_music/features/music_platform/netease/netease_item_artwork.dart';
import 'package:mesting_music/features/player/presentation/music_page_transition.dart';
import 'package:mesting_music/shared/widgets/beta_page_motion.dart';
import 'release_148_data_test.dart' show Metadata148;

void main() {
  test(
    'cover retry bypasses observed old responses without changing other queries',
    () async {
      final observed = <bool>[];
      final repository = Metadata148((route, query) async {
        observed.add(BrowseResponseCache.observing);
        return {
          'playlists': [
            {
              'id': 1,
              'coverImgUrl': BrowseResponseCache.observing
                  ? 'https://p1.music.126.net/old.jpg'
                  : 'https://p1.music.126.net/fresh.jpg',
            },
          ],
        };
      });
      final artwork = NeteaseArtworkRepository(repository);
      final watch = BrowseCacheWatch(() {});
      addTearDown(watch.dispose);
      expect(
        await watch.run(() => artwork.category('综艺')),
        'https://p1.music.126.net/old.jpg',
      );
      expect(
        await watch.run(
          () => artwork.category(
            '综艺',
            refresh: true,
            rejected: 'https://p1.music.126.net/old.jpg',
          ),
        ),
        'https://p1.music.126.net/fresh.jpg',
      );
      expect(observed, [true, false]);
      expect(BrowseResponseCache.observing, isFalse);
    },
  );
  test(
    'empty category cover retrieves its real playlist and album cover',
    () async {
      final repository = Metadata148(
        (route, query) async => route == '/top/playlist'
            ? {
                'playlists': [
                  {'id': 25, 'coverImgUrl': ''},
                ],
              }
            : {
                'playlist': {
                  'id': 25,
                  'tracks': [
                    {
                      'al': {
                        'picUrl': 'https://p1.music.126.net/real-album.jpg',
                      },
                    },
                  ],
                },
              },
      );
      final artwork = NeteaseArtworkRepository(repository);
      expect(
        await artwork.category('综艺'),
        'https://p1.music.126.net/real-album.jpg',
      );
      expect(repository.calls.last.$2['id'], '25');
    },
  );
  test(
    'recovery skips rejected thumbnail identities and tries another category playlist',
    () async {
      final repository = Metadata148(
        (route, query) async => route == '/top/playlist'
            ? {
                'playlists': [
                  {
                    'id': 1,
                    'coverImgUrl':
                        'https://p2.music.126.net/bad.jpg?param=120y120',
                  },
                  {'id': 2, 'coverImgUrl': 'https://p1.music.126.net/good.jpg'},
                ],
              }
            : {
                'playlist': {
                  'coverImgUrl': 'https://p1.music.126.net/bad.jpg?param=60y60',
                },
              },
      );
      expect(
        await NeteaseArtworkRepository(repository).category(
          '综艺',
          refresh: true,
          rejected: 'https://p1.music.126.net/bad.jpg?param=200y200',
        ),
        'https://p1.music.126.net/good.jpg',
      );
      expect(repository.calls.first.$2['limit'], 6);
    },
  );
  test(
    'manual category recovery remains bounded to three simultaneous requests',
    () async {
      var active = 0, maximum = 0;
      final gate = Completer<void>();
      final repository = Metadata148((route, query) async {
        active++;
        if (active > maximum) maximum = active;
        await gate.future;
        active--;
        return {
          'playlists': [
            {
              'id': query['cat'],
              'coverImgUrl': 'https://p1.music.126.net/${query['cat']}.jpg',
            },
          ],
        };
      });
      final art = NeteaseArtworkRepository(repository);
      final work = Future.wait([
        for (var i = 0; i < 12; i++) art.category('cat$i', refresh: true),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(maximum, 3);
      gate.complete();
      await work;
      expect(maximum, 3);
      expect(active, 0);
    },
  );
  test('visibility and opacity use the same entry threshold in reverse', () {
    for (final threshold in [.18, .42]) {
      for (final value in [.01, .17, .19, .41, .43, .57, .59, .99]) {
        final visible = musicPageLayerIsVisible(
          primaryStatus: AnimationStatus.reverse,
          primaryValue: value,
          secondaryStatus: AnimationStatus.dismissed,
          secondaryValue: 0,
          handoffProgress: threshold,
        );
        final opacity = musicPageLayerOpacity(
          primaryStatus: AnimationStatus.reverse,
          primaryValue: value,
          secondaryStatus: AnimationStatus.dismissed,
          secondaryValue: 0,
          handoffProgress: threshold,
        );
        expect(visible, value > threshold);
        expect(opacity, visible ? 1 : 0);
      }
    }
  });
  for (final routeKind in ['router-page', 'material']) {
    testWidgets(
      'live $routeKind exits along the same path and retains the parent',
      (tester) async {
        final key = GlobalKey<NavigatorState>();
        var counter = 0;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: key,
            theme: ThemeData(
              pageTransitionsTheme: const PageTransitionsTheme(
                builders: {
                  TargetPlatform.android: BetaPageTransitionsBuilder(),
                  TargetPlatform.iOS: BetaPageTransitionsBuilder(),
                  TargetPlatform.windows: BetaPageTransitionsBuilder(),
                },
              ),
            ),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: TextButton(
                  onPressed: () => setState(() => counter++),
                  child: Text('parent:$counter'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('parent:0'));
        await tester.pump();
        const page = Scaffold(
          body: Center(
            child: Text('destination', key: ValueKey('destination')),
          ),
        );
        final route = routeKind == 'router-page'
            ? const BetaContentTransitionPage<void>(
                child: page,
              ).createRoute(key.currentContext!)
            : MestingPageRoute<void>(builder: (_) => page);
        expect((route as PageRoute<void>).allowSnapshotting, isFalse);
        unawaited(key.currentState!.push(route));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final entry = tester
            .getCenter(find.byKey(const ValueKey('destination')))
            .dx;
        expect(entry, greaterThan(400));
        await tester.pumpAndSettle();
        expect(
          tester.getCenter(find.byKey(const ValueKey('destination'))).dx,
          closeTo(400, 1),
        );
        key.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester.getCenter(find.byKey(const ValueKey('destination'))).dx,
          greaterThan(400),
        );
        await tester.pumpAndSettle();
        expect(find.text('parent:1'), findsOneWidget);
        expect(counter, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
