import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_design.dart';
import 'package:mesting_music/shared/media/artwork_refresh_coordinator.dart';
import 'package:mesting_music/shared/media/persistent_network_image_cache.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/shared/widgets/artwork_reveal_boundary.dart';
import 'package:mesting_music/shared/widgets/mesting_loading_indicator.dart';

const _capture = ValueKey('capture');
const _red = Color(0xFFFF0000), _green = Color(0xFF00FF00);

Future<int> coloredPixels(WidgetTester tester, Color color) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  if (boundary.debugNeedsPaint) await tester.pump();
  // Request the snapshot before yielding to real I/O: a newly decoded image
  // can otherwise dirty the layer between pump() and toImage().
  final captured = boundary.toImage();
  return (await tester.runAsync(() async {
    final image = await captured;
    final bytes = (await image.toByteData())!.buffer.asUint8List();
    var count = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      if (bytes[i] == color.r * 255 &&
          bytes[i + 1] == color.g * 255 &&
          bytes[i + 2] == color.b * 255) {
        count++;
      }
    }
    image.dispose();
    return count;
  }))!;
}

Future<Uint8List> bluePng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xFF0000FF), BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(192, 192);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

Future<void> captureFrame(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('EXPORT_REVEAL_FRAMES')) return;
  await tester.pump();
  final shot = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(_capture))
      .toImage();
  await tester.runAsync(() async {
    final image = await shot;
    final png = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    final directory = Directory('.codex-artifacts/2026-11-01-release130/ui')
      ..createSync(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(png);
    image.dispose();
  });
}

/// Hold requests independently, including the nearby lazy cache extent. Each
/// test uses a unique private directory, so a rerun cannot become a disk hit.
class _Fixture {
  _Fixture(this.png) {
    final directory = Directory(
      '.codex-artifacts/2026-11-01-release130/fixtures/${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    cache = PersistentNetworkImageCache(
      directoryProvider: () async => directory,
      client: MockClient((request) {
        final path = request.url.path;
        requests.add(path);
        if (ready.contains(path)) {
          return Future.value(http.Response.bytes(png, 200));
        }
        return (pending[path] ??= Completer<http.Response>()).future;
      }),
    );
  }
  final Uint8List png;
  final ready = <String>{}, requests = <String>{};
  final built = <String>{};
  final pending = <String, Completer<http.Response>>{};
  late final PersistentNetworkImageCache cache;
  void complete(String path, {int status = 200}) {
    if (status == 200) ready.add(path);
    final request = pending[path];
    if (request != null && !request.isCompleted) {
      request.complete(http.Response.bytes(png, status));
    }
  }

  Widget row(String path, {Color marker = _red, VoidCallback? onTap}) {
    built.add(path);
    return Row(
      children: [
        ArtworkImage(
          uri: 'https://image.example$path',
          width: 52,
          height: 52,
          networkImageCache: cache,
          persistentNetworkCacheKey: 'public-artwork-v1',
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 80,
            height: 40,
            child: ColoredBox(color: marker),
          ),
        ),
        const Expanded(child: Text('Secret row title')),
      ],
    );
  }

  Future<void> close(WidgetTester tester) async {
    // Finish prefetch too, leaving no fake-async HTTP timeout at teardown.
    for (final path in built.toList()) {
      complete(path);
    }
    final remaining = built.toSet();
    for (final path in built.toList()) {
      unawaited(
        cache
            .resolve(
              cacheKey: 'public-artwork-v1',
              url: 'https://image.example$path',
            )
            .then((_) => remaining.remove(path)),
      );
    }
    // Pump the fake clock as well as real file I/O. Awaiting a Future created
    // in the fake-async zone solely inside runAsync would strand its callbacks.
    await waitFor(tester, () => remaining.isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    artworkRefreshCoordinator.dispose();
    imageCache.clear();
    imageCache.clearLiveImages();
    // Host file codecs may still hold mapped bytes. Keep private fixtures until
    // the test process exits; never recursively delete product cache/data.
  }
}

Widget app(Widget child) => MaterialApp(
  theme: buildMestingTheme(musicThemePresetById('classic')),
  home: RepaintBoundary(
    key: _capture,
    child: PlatformPageFrame(
      title: 'Content',
      musicChrome: false,
      child: child,
    ),
  ),
);

Future<void> waitFor(WidgetTester tester, bool Function() condition) async {
  // Native file codecs and scheduled widget frames use different clocks.
  // Give both bounded progress, keeping the virtual interval below the first
  // automatic retry (650ms) so retry/error assertions retain their meaning.
  for (var n = 0; n < 300 && !condition(); n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue);
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('EXPORT_REVEAL_FRAMES')) {
      await (FontLoader('Roboto')..addFont(
            File(
              'C:/Windows/Fonts/msyh.ttc',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            File(
              'D:/CodexCache/flutter-3.41.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    }
  });

  testWidgets(
    'multiple pending data sections share the first-screen gate before any covers exist',
    (tester) async {
      var first = true, second = true;
      late StateSetter update;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return Column(
                children: [
                  const SizedBox(
                    width: 80,
                    height: 40,
                    child: ColoredBox(color: _red),
                  ),
                  if (first) const MestingLoadingIndicator(),
                  if (second) const MestingLoadingIndicator(),
                ],
              );
            },
          ),
        ),
      );
      expect(await coloredPixels(tester, _red), 0);
      update(() => first = false);
      await tester.pump();
      expect(await coloredPixels(tester, _red), 0);
      update(() => second = false);
      await tester.pump();
      expect(await coloredPixels(tester, _red), greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'an unresolved cover reaches explicit retry instead of holding the viewport forever',
    (tester) async {
      final fixture = _Fixture((await tester.runAsync(bluePng))!);
      await tester.runAsync(fixture.cache.initialize);
      await tester.pumpWidget(
        app(Column(children: [fixture.row('/slow.png')])),
      );
      await waitFor(tester, () => fixture.requests.contains('/slow.png'));
      expect(await coloredPixels(tester, _red), 0);
      await tester.pump(const Duration(seconds: 21));
      await tester.pump();
      await tester.pump();
      expect(find.text('重试'), findsOneWidget);
      expect(await coloredPixels(tester, _red), greaterThan(0));
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'common page reveals first-screen text only with decoded artwork, semantics and taps',
    (tester) async {
      final fixture = _Fixture((await tester.runAsync(bluePng))!);
      await tester.runAsync(fixture.cache.initialize);
      var taps = 0;
      // A negative control proves the pixel assertion detects unguarded metadata.
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: _capture,
            child: Scaffold(body: fixture.row('/first.png')),
          ),
        ),
      );
      expect(await coloredPixels(tester, _red), greaterThan(0));
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(Column(children: [fixture.row('/first.png', onTap: () => taps++)])),
      );
      expect(await coloredPixels(tester, _red), 0);
      await captureFrame(tester, 'first-visit-unified-loading');
      expect(
        tester.getSemantics(find.byKey(_capture)).toStringDeep(),
        isNot(contains('Secret row title')),
      );
      await tester.tapAt(
        tester.getTopLeft(find.byType(ArtworkImage)) + const Offset(90, 20),
      );
      expect(taps, 0);
      await waitFor(tester, () => fixture.requests.contains('/first.png'));
      fixture.complete('/first.png');
      await waitFor(tester, () => find.byType(RawImage).evaluate().isNotEmpty);
      expect(await coloredPixels(tester, _red), greaterThan(0));
      await tester.tapAt(
        tester.getTopLeft(find.byType(ArtworkImage)) + const Offset(90, 20),
      );
      expect(taps, 1);
      await captureFrame(tester, 'first-visit-ready-together');
      expect(find.byIcon(Icons.album_rounded), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await fixture.close(tester);
    },
  );

  testWidgets(
    'scroll keeps old rows and reveals a new visible batch together',
    (tester) async {
      tester.view.physicalSize = const Size(400, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _Fixture((await tester.runAsync(bluePng))!);
      fixture.ready.addAll([for (var i = 0; i < 8; i++) '/$i.png']);
      await tester.runAsync(fixture.cache.initialize);
      final scroll = ScrollController();
      await tester.pumpWidget(
        app(
          ListView.builder(
            controller: scroll,
            itemCount: 1000,
            itemExtent: 80,
            itemBuilder: (_, index) =>
                fixture.row('/$index.png', marker: index < 8 ? _red : _green),
          ),
        ),
      );
      final controller = ArtworkRevealBoundary.of(
        tester.element(find.byType(ArtworkImage).first),
      )!;
      await waitFor(tester, () => !controller.pending.value);
      expect(await coloredPixels(tester, _red), greaterThan(0));
      scroll.jumpTo(320);
      await tester.pump();
      expect(await coloredPixels(tester, _red), greaterThan(0));
      expect(await coloredPixels(tester, _green), 0);
      await captureFrame(tester, 'scroll-next-batch-loading');
      await waitFor(tester, () => fixture.requests.contains('/8.png'));
      fixture.complete('/8.png');
      await waitFor(
        tester,
        () => controller.entries
            .where((e) => e.identity.endsWith('/8.png') && !e.ready)
            .isEmpty,
      );
      await tester.pump();
      expect(
        await coloredPixels(tester, _green),
        0,
        reason: 'An early cover waits for its visible batch.',
      );
      for (var i = 9; i <= 11; i++) {
        fixture.complete('/$i.png');
      }
      await waitFor(
        tester,
        () => controller.entries
            .where(
              (e) =>
                  !e.ready && e.identity.contains(RegExp(r'/(8|9|10|11)\.png')),
            )
            .isEmpty,
      );
      expect(await coloredPixels(tester, _green), greaterThan(0));
      await captureFrame(tester, 'scroll-next-batch-ready');
      expect(
        fixture.requests.length,
        lessThan(25),
        reason: 'Never preload the entire library.',
      );
      scroll.jumpTo(0);
      await tester.pump();
      scroll.jumpTo(320);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
      scroll.dispose();
    },
  );

  testWidgets('one failed cover offers retry without holding successful rows', (
    tester,
  ) async {
    final fixture = _Fixture((await tester.runAsync(bluePng))!);
    await tester.runAsync(fixture.cache.initialize);
    await tester.pumpWidget(
      app(
        Column(
          children: [fixture.row('/good.png'), fixture.row('/failed.png')],
        ),
      ),
    );
    await waitFor(tester, () => fixture.requests.length == 2);
    fixture.complete('/good.png');
    fixture.complete('/failed.png', status: 503);
    await waitFor(
      tester,
      () =>
          find.text('重试').evaluate().isNotEmpty &&
          find.byType(RawImage).evaluate().isNotEmpty,
    );
    expect(await coloredPixels(tester, _red), greaterThan(0));
    expect(find.byIcon(Icons.album_rounded), findsNothing);
    fixture.ready.add('/failed.png');
    await captureFrame(tester, 'failed-cover-explicit-retry');
    await tester.tap(find.text('重试'));
    await waitFor(tester, () => find.byType(RawImage).evaluate().length == 2);
    expect(tester.takeException(), isNull);
    await fixture.close(tester);
  });

  testWidgets(
    'prepared thumbnail paints immediately while a larger request waits',
    (tester) async {
      final fixture = _Fixture((await tester.runAsync(bluePng))!);
      await tester.runAsync(fixture.cache.initialize);
      final codec = (await tester.runAsync(
        () => ui.instantiateImageCodec(fixture.png),
      ))!;
      final frame = (await tester.runAsync(codec.getNextFrame))!;
      final info = ImageInfo(image: frame.image);
      artworkRefreshCoordinator.remember(
        'https://image.example/thumbnail.png',
        info,
      );
      info.dispose();
      codec.dispose();
      await tester.pumpWidget(
        app(Column(children: [fixture.row('/thumbnail.png')])),
      );
      expect(await coloredPixels(tester, _red), greaterThan(0));
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );
}
