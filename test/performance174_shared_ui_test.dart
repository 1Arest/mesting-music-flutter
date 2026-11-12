import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/experience/presentation/editorial_widgets.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/retained_platform_snapshot.dart';
import 'package:mesting_music/shared/media/persistent_network_image_cache.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/shared/widgets/retained_artwork_frame.dart';

class _RefreshAccount174 extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async =>
      const PlatformSession(userId: 'synthetic-one', token: 'first');

  void refreshSameOwner() {
    // Reproduce the retained loading state Riverpod publishes internally for
    // a real account refresh; this synthetic test does not refresh credentials.
    // ignore: invalid_use_of_internal_member
    state = const AsyncLoading<PlatformSession?>().copyWithPrevious(state);
  }

  void changeOwner() => state = const AsyncData(
    PlatformSession(userId: 'synthetic-two', token: 'second'),
  );
}

class _PendingCache174 extends PersistentNetworkImageCache {
  final pending = <String, Completer<File?>>{};
  var calls = 0;

  @override
  bool get initialized => true;

  @override
  File? peek({required String cacheKey, required String url}) => null;

  @override
  File? peekContent({required String cacheKey, required String url}) => null;

  @override
  Future<File?> resolve({required String cacheKey, required String url}) {
    calls++;
    return (pending[url] ??= Completer<File?>()).future;
  }
}

class _CountingImage174 extends ImageProvider<_CountingImage174> {
  _CountingImage174(this.image);
  final ui.Image image;
  var resolutions = 0;

  @override
  Future<_CountingImage174> obtainKey(ImageConfiguration configuration) {
    resolutions++;
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CountingImage174 key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    SynchronousFuture(ImageInfo(image: image.clone())),
  );
}

class _Resources174 {
  const _Resources174(this.revision);
  final int revision;
}

/// Changes localization resources without changing the image's locale or
/// decoder size. This is a real dependency notification, not a State hook.
class _ResourcesDelegate174 extends LocalizationsDelegate<_Resources174> {
  const _ResourcesDelegate174(this.revision);
  final int revision;
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<_Resources174> load(Locale locale) =>
      SynchronousFuture(_Resources174(revision));
  @override
  bool shouldReload(_ResourcesDelegate174 old) => revision != old.revision;
}

void main() {
  testWidgets('editorial shelves mount only the viewport and nearby prefetch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final built = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorialScroll(
            children: [
              for (var i = 0; i < 60; i++)
                Builder(
                  builder: (_) {
                    built.add(i);
                    return SizedBox(height: 100, child: Text('shelf-$i'));
                  },
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    debugPrint('174 lazy shelves: ${built.length} initially mounted of 60');
    expect(built.length, lessThan(12));
    expect(built, contains(0));
    expect(built, isNot(contains(30)));
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(2700);
    await tester.pump();
    expect(built.any((i) => i >= 27 && i <= 33), isTrue);
    expect(built, isNot(contains(59)));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('editorial lazy boxes preserve real sliver ordering and footer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorialScroll(
            footer: const Text('final-footer'),
            children: const [
              SizedBox(height: 80, child: Text('box-before')),
              EditorialSliver(
                sliver: SliverToBoxAdapter(
                  child: SizedBox(height: 80, child: Text('real-sliver')),
                ),
              ),
              SizedBox(height: 80, child: Text('box-after')),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.text('box-before')).dy,
      lessThan(tester.getTopLeft(find.text('real-sliver')).dy),
    );
    expect(
      tester.getTopLeft(find.text('real-sliver')).dy,
      lessThan(tester.getTopLeft(find.text('box-after')).dy),
    );
    expect(
      tester.getTopLeft(find.text('box-after')).dy,
      lessThan(tester.getTopLeft(find.text('final-footer')).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'same-account revalidation retains data; a new owner removes it',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          platformAccountProvider.overrideWith(_RefreshAccount174.new),
        ],
      );
      await container.read(platformAccountProvider.future);
      AsyncValue<String> content = const AsyncData('cached-current-owner');
      late StateSetter update;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return RetainedPlatformSnapshot<String>(
                  value: content,
                  loading: () => const Text('loading-new-owner'),
                  error: (_, _) => const Text('load-error'),
                  data: Text.new,
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('cached-current-owner'), findsOneWidget);
      final account =
          container.read(platformAccountProvider.notifier)
              as _RefreshAccount174;
      account.refreshSameOwner();
      // Hold the content refresh independently from the credential refresh.
      // Production FutureProviders do exactly this while their network is slow.
      update(() => content = const AsyncLoading<String>());
      await tester.pump();
      expect(find.text('cached-current-owner'), findsOneWidget);
      expect(find.text('loading-new-owner'), findsNothing);
      account.changeOwner();
      await tester.pump();
      expect(find.text('cached-current-owner'), findsNothing);
      expect(find.text('loading-new-owner'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );

  testWidgets('a pending thumbnail has one callback across hide and resume', (
    tester,
  ) async {
    final cache = _PendingCache174();
    var active = true;
    var uri = 'https://images.example.test/a';
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return TickerMode(
              enabled: active,
              child: ArtworkImage(
                uri: uri,
                networkImageCache: cache,
                persistentNetworkCacheKey: 'synthetic174',
                width: 48,
                height: 48,
              ),
            );
          },
        ),
      ),
    );
    expect(cache.calls, 1);
    for (var i = 0; i < 3; i++) {
      update(() => active = false);
      await tester.pump();
      update(() => active = true);
      await tester.pump();
    }
    expect(cache.calls, 1);
    update(() => uri = 'https://images.example.test/b');
    await tester.pump();
    expect(cache.calls, 2);
    // A failed outgoing cover must not mark the new pending cover as failed.
    cache.pending.entries.first.value.complete(null);
    await tester.pump();
    expect(find.text('重试'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    for (final pending in cache.pending.values) {
      if (!pending.isCompleted) pending.complete(null);
    }
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ready cover skips redundant resolve but honors DPR and retry', (
    tester,
  ) async {
    final image = (await tester.runAsync(
      () => createTestImage(width: 4, height: 4),
    ))!;
    final provider = _CountingImage174(image);
    var resources = 0, retry = 0;
    var ratio = 1.0;
    var enabled = true;
    late StateSetter update;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (_, setState) {
          update = setState;
          return MediaQuery(
            data: MediaQueryData(devicePixelRatio: ratio),
            child: Localizations(
              locale: const Locale('en'),
              delegates: [
                DefaultWidgetsLocalizations.delegate,
                _ResourcesDelegate174(resources),
              ],
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: TickerMode(
                  enabled: enabled,
                  child: RetainedArtworkFrame(
                    uri: 'https://images.example.test/synthetic174',
                    image: provider,
                    retryRevision: retry,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    fallback: const SizedBox(),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.pump();
    expect(provider.resolutions, 1);
    update(() => resources++);
    await tester.pump();
    expect(provider.resolutions, 1);
    update(() => ratio = 2);
    await tester.pump();
    expect(provider.resolutions, 2);
    update(() => retry++);
    await tester.pump();
    expect(provider.resolutions, 3);
    update(() => enabled = false);
    await tester.pump();
    expect(provider.resolutions, 3);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    update(() => enabled = true);
    await tester.pump();
    expect(provider.resolutions, 4);
    await tester.pumpWidget(const SizedBox());
    image.dispose();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    expect(tester.takeException(), isNull);
  });
}
