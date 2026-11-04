import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/app/router/beta_tab_shell.dart';
import 'package:mesting_music/core/cache/browse_response_cache.dart';
import 'package:mesting_music/shared/media/artwork_refresh_coordinator.dart';
import 'package:mesting_music/shared/media/persistent_network_image_cache.dart';
import 'package:mesting_music/shared/widgets/beta_bottom_search.dart';
import 'package:mesting_music/shared/widgets/beta_root_tab_viewport.dart';
import 'package:mesting_music/shared/widgets/retained_artwork_frame.dart';
import 'package:mesting_music/shared/utils/media_uri.dart';

Future<ui.Image> _pixels(Color color, {int width = 2, int height = 2}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

Future<Uint8List> _png(Color color, {int width = 2, int height = 2}) async {
  final image = await _pixels(color, width: width, height: height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

class _Frames extends ImageStreamCompleter {
  void emit(ui.Image image) => setImage(ImageInfo(image: image.clone()));
  void fail() => reportError(
    exception: StateError('synthetic decode error'),
    context: ErrorDescription('controlled image'),
  );
}

class _ControlledImage extends ImageProvider<_ControlledImage> {
  _ControlledImage(this.frames);
  final _Frames frames;
  @override
  Future<_ControlledImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    _ControlledImage key,
    ImageErrorListener handleError,
  ) => stream.setCompleter(frames);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List red, blue;
  setUpAll(() async {
    red = await _png(Colors.red);
    blue = await _png(Colors.blue);
  });

  for (final outcome in ['ready', 'failed', 'account changed']) {
    test(
      'response stays durable and visible until decoded image is ready: $outcome',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'mesting-128-ready-',
        );
        final response = Completer<http.Response>();
        final started = Completer<void>();
        final images = PersistentNetworkImageCache(
          directoryProvider: () async => directory,
          client: MockClient((request) async {
            if (request.url.path == '/old.png') {
              return http.Response.bytes(red, 200);
            }
            if (!started.isCompleted) started.complete();
            return response.future;
          }),
        );
        final coordinator = ArtworkRefreshCoordinator(cache: images);
        final cache = BrowseResponseCache(
          directory: () async => directory,
          initializeOnRead: true,
        );
        final preparation = Completer<bool>();
        cache.prepareCached = coordinator.prepareCached;
        cache.prepareRefresh = (previous, incoming) async {
          final ready = await coordinator.prepareRefresh(previous, incoming);
          if (!preparation.isCompleted) preparation.complete(ready);
          return ready;
        };
        var generation = 0, notices = 0;
        var body = <String, dynamic>{
          'code': 200,
          'title': 'old',
          'picUrl': 'https://image.example/old.png',
        };
        final watch = BrowseCacheWatch(() => notices++, forceRefresh: true);
        Future<Map<String, dynamic>> read() => watch.run(
          () => cache.read(
            scope: 'netease:fixture',
            route: 'browse',
            query: {},
            requestIdentity: 'synthetic',
            checkCurrent: () {
              if (generation != 0) throw StateError('account changed');
            },
            load: () async => body,
          ),
        );
        await read();
        await images.resolve(
          cacheKey: 'public-artwork-v1',
          url: body['picUrl'] as String,
        );
        body = {
          'code': 200,
          'title': 'new',
          'picUrl': 'https://image.example/new.png',
        };
        final cached = await read();
        await started.future;
        expect(cached['title'], 'old');
        expect(notices, 0);
        final file = Directory(
          '${directory.path}/mesting_browse_cache_v1',
        ).listSync().whereType<File>().single;
        expect(
          (jsonDecode(await file.readAsString())['body'] as Map)['title'],
          'old',
        );
        if (outcome == 'account changed') generation++;
        response.complete(
          http.Response.bytes(blue, outcome == 'failed' ? 503 : 200),
        );
        await preparation.future;
        await Future<void>.delayed(const Duration(milliseconds: 15));
        if (outcome == 'ready') {
          final deadline = DateTime.now().add(const Duration(seconds: 3));
          while (notices == 0 && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(notices, 1);
          final ready = coordinator.take('https://image.example/new.png');
          expect(ready, isNotNull);
          expect(ready!.image.width, 2);
          ready.dispose();
          expect(
            (jsonDecode(await file.readAsString())['body'] as Map)['title'],
            'new',
          );
        } else {
          expect(notices, 0);
          expect(
            (jsonDecode(await file.readAsString())['body'] as Map)['title'],
            'old',
          );
        }
        watch.dispose();
        coordinator.dispose();
        await directory.delete(recursive: true);
      },
    );
  }

  test(
    'cold cache restores the previous thumbnail and decodes before returning',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mesting-128-cold-',
      );
      final wide = await _png(Colors.red, width: 512, height: 256);
      final first = PersistentNetworkImageCache(
        directoryProvider: () async => directory,
        client: MockClient((_) async => http.Response.bytes(wide, 200)),
      );
      await first.resolve(
        cacheKey: 'public-artwork-v1',
        url: 'https://p1.music.126.net/fixture.png?param=216y216',
      );
      var requests = 0;
      final restored = PersistentNetworkImageCache(
        directoryProvider: () async => directory,
        client: MockClient((_) async {
          requests++;
          throw StateError('offline');
        }),
      );
      await restored.initialize();
      final coordinator = ArtworkRefreshCoordinator(cache: restored);
      await coordinator.prepareCached({
        'picUrl': 'https://p1.music.126.net/fixture.png',
      });
      final frame = coordinator.take(
        'https://p1.music.126.net/fixture.png?param=216y216',
      );
      expect(frame, isNotNull);
      expect(requests, 0);
      expect(frame!.image.width / frame.image.height, closeTo(2, .01));
      frame.dispose();
      coordinator.dispose();
      await directory.delete(recursive: true);
    },
  );

  test(
    'prepared frames isolate owners and unknown-host tokens without losing CDN reuse',
    () async {
      final coordinator = ArtworkRefreshCoordinator();
      final image = await _pixels(Colors.red);
      final info = ImageInfo(image: image.clone());
      coordinator.remember(
        'https://image.example/a.png',
        info,
        scope: 'owner-A',
      );
      expect(
        coordinator.take('https://image.example/a.png', scope: 'owner-B'),
        isNull,
      );
      final frame = coordinator.take(
        'https://image.example/a.png',
        scope: 'owner-A',
      );
      expect(frame, isNotNull);
      frame!.dispose();
      info.dispose();
      image.dispose();
      coordinator.dispose();
      expect(
        artworkContentIdentity('https://private.example/img?token=A'),
        isNot(artworkContentIdentity('https://private.example/img?token=B')),
      );
      expect(
        artworkContentIdentity(
          'https://p1.music.126.net/img.jpg?param=216y216&token=A',
        ),
        artworkContentIdentity(
          'https://p1.music.126.net/img.jpg?param=768y768&token=B',
        ),
      );
    },
  );
  testWidgets(
    'image replacement keeps a decoded frame through pending and error, then uses prepared pixels immediately',
    (tester) async {
      final first = _Frames(), second = _Frames(), third = _Frames();
      final redImage = await tester.runAsync(() => _pixels(Colors.red));
      final blueImage = await tester.runAsync(() => _pixels(Colors.blue));
      var failures = 0;
      Widget host(
        String uri,
        _Frames frames, {
        String scope = 'public-artwork-v1',
      }) => MaterialApp(
        home: Center(
          child: RetainedArtworkFrame(
            uri: uri,
            scope: scope,
            image: _ControlledImage(frames),
            fallback: const Text('placeholder'),
            width: 100,
            height: 100,
            fit: BoxFit.cover,
            onError: (_, _) => failures++,
          ),
        ),
      );
      await tester.pumpWidget(host('https://image.example/a.png', first));
      expect(find.text('placeholder'), findsOneWidget);
      first.emit(redImage!);
      await tester.pump();
      expect(
        tester
            .widget<RawImage>(find.byType(RawImage))
            .image!
            .isCloneOf(redImage),
        isTrue,
      );
      await tester.pumpWidget(host('https://image.example/b.png', second));
      expect(find.text('placeholder'), findsNothing);
      expect(
        tester
            .widget<RawImage>(find.byType(RawImage))
            .image!
            .isCloneOf(redImage),
        isTrue,
      );
      second.fail();
      await tester.pump();
      expect(failures, 1);
      expect(find.text('placeholder'), findsNothing);
      final info = ImageInfo(image: blueImage!.clone());
      artworkRefreshCoordinator.remember(
        'https://image.example/c.png',
        info,
        pin: true,
      );
      info.dispose();
      await tester.pumpWidget(host('https://image.example/c.png', third));
      expect(
        tester
            .widget<RawImage>(find.byType(RawImage))
            .image!
            .isCloneOf(blueImage),
        isTrue,
      );
      expect(find.text('placeholder'), findsNothing);
      await tester.pumpWidget(
        host('https://image.example/c.png', _Frames(), scope: 'new-owner'),
      );
      expect(
        find.text('placeholder'),
        findsOneWidget,
        reason: 'Another owner must not inherit the previous frame.',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      redImage.dispose();
      blueImage.dispose();
      artworkRefreshCoordinator.dispose();
    },
  );

  test(
    'image preparation limits parallel requests and retains no partial snapshot on memory pressure',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mesting-128-budget-',
      );
      var active = 0, peak = 0;
      final cache = PersistentNetworkImageCache(
        directoryProvider: () async => directory,
        client: MockClient((_) async {
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          active--;
          return http.Response.bytes(red, 200);
        }),
      );
      final coordinator = ArtworkRefreshCoordinator(cache: cache, maxBytes: 16);
      final ready = await coordinator.prepareRefresh({}, {
        'data': [
          for (var i = 0; i < 6; i++)
            {'picUrl': 'https://image.example/budget$i.png'},
        ],
      });
      expect(ready, isFalse);
      expect(peak, inInclusiveRange(1, 3));
      var stored = 0;
      for (var i = 0; i < 6; i++) {
        final frame = coordinator.take('https://image.example/budget$i.png');
        if (frame != null) {
          stored++;
          frame.dispose();
        }
      }
      expect(stored, 1);
      coordinator.dispose();
      await directory.delete(recursive: true);
    },
  );

  test(
    'an empty replacement for an already displayed cover keeps the old snapshot',
    () async {
      final coordinator = ArtworkRefreshCoordinator();
      final entry = coordinator.register(() => true)
        ..source = 'https://image.example/old.png';
      final ready = await coordinator.prepareRefresh(
        {'picUrl': entry.source},
        {'picUrl': ''},
      );
      expect(ready, isFalse);
      coordinator.dispose();
    },
  );

  testWidgets(
    'rapid tabs retarget without a jump and keep at most two viewport render children',
    (tester) async {
      var selected = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return BetaRootTabViewport(
                index: selected,
                children: [
                  for (var i = 0; i < 4; i++)
                    ColoredBox(color: Colors.white, child: Text('tab$i')),
                ],
              );
            },
          ),
        ),
      );
      final controller = tester
          .widget<PageView>(
            find.byKey(const ValueKey('beta-root-tab-viewport')),
          )
          .controller!;
      update(() => selected = 3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final before = controller.page!;
      expect(before, greaterThan(0));
      update(() => selected = 0);
      await tester.pump();
      expect(controller.page, closeTo(before, .001));
      await tester.pump(const Duration(milliseconds: 40));
      expect(controller.page, lessThan(before));
      for (final target in [2, 1, 3, 0, 2, 3, 1, 0]) {
        update(() => selected = target);
        final previous = controller.page!;
        await tester.pump();
        expect(controller.page, closeTo(previous, .001));
        await tester.pump(const Duration(milliseconds: 16));
        RenderSliverFillViewport? found;
        void visit(RenderObject object) {
          if (object is RenderSliverFillViewport) {
            found = object;
          } else {
            object.visitChildren(visit);
          }
        }

        visit(tester.renderObject(find.byType(SliverFillViewport)));
        final sliver = found!;
        var count = 0;
        RenderBox? child = sliver.firstChild;
        while (child != null) {
          count++;
          child = sliver.childAfter(child);
        }
        expect(count, lessThanOrEqualTo(2));
      }
      await tester.pumpAndSettle();
      expect(controller.page, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'production nested tab shell keeps outer chrome, branch state, detail back and search ownership',
    (tester) async {
      const paths = ['/discover', '/music', '/library', '/profile'];
      final host = BetaBottomSearchHost(
        location: paths[0],
        openMusicSearch: () {},
      );
      final controllers = [
        for (var i = 0; i < 4; i++)
          BetaPageSearchController(
            hintText: 'search$i',
            onSubmitted: (_) {},
            onCleared: () {},
          ),
      ];
      final router = GoRouter(
        initialLocation: paths[0],
        routes: [
          ShellRoute(
            builder: (context, state, child) {
              host.location = state.uri.path;
              return BetaBottomSearchScope(
                host: host,
                child: Scaffold(
                  key: const ValueKey('outer-shell'),
                  body: child,
                ),
              );
            },
            routes: [
              ...betaTabShellRoutes([
                for (var i = 0; i < 4; i++)
                  GoRoute(
                    path: paths[i],
                    pageBuilder: (_, state) => NoTransitionPage(
                      key: state.pageKey,
                      child: BetaBottomSearchBinding(
                        controller: controllers[i],
                        child: _CounterTab(index: i),
                      ),
                    ),
                  ),
              ]),
              GoRoute(path: '/detail', builder: (_, _) => const Text('detail')),
            ],
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go(paths[1]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('count1:0'));
      await tester.pump();
      router.go(paths[3]);
      await tester.pump(const Duration(milliseconds: 30));
      router.go(paths[0]);
      await tester.pump(const Duration(milliseconds: 30));
      router.go(paths[1]);
      await tester.pumpAndSettle();
      expect(find.text('count1:1').hitTestable(), findsOneWidget);
      expect(host.current, controllers[1]);
      final shell = tester.element(find.byKey(const ValueKey('outer-shell')));
      unawaited(router.push('/detail'));
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byKey(const ValueKey('outer-shell'))),
        same(shell),
      );
      expect(host.current, isNull);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('count1:1').hitTestable(), findsOneWidget);
      expect(host.current, controllers[1]);
      final pushedView = router.push('/music?view=daily');
      await tester.pumpAndSettle();
      expect(find.text('count1:0').hitTestable(), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      await pushedView;
      expect(find.text('count1:1').hitTestable(), findsOneWidget);
      router.go('/music?view=daily');
      await tester.pump(const Duration(milliseconds: 16));
      router.go(paths[0]);
      await tester.pump(const Duration(milliseconds: 16));
      router.go(paths[3]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      host.dispose();
      for (final controller in controllers) {
        controller.dispose();
      }
    },
  );
}

class _CounterTab extends StatefulWidget {
  const _CounterTab({required this.index});
  final int index;
  @override
  State<_CounterTab> createState() => _CounterTabState();
}

class _CounterTabState extends State<_CounterTab> {
  var count = 0;
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => count++),
      child: Text('count${widget.index}:$count'),
    ),
  );
}
