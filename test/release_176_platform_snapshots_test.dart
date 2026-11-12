import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_display_snapshots.dart';
import 'package:mesting_music/features/music_platform/presentation/retained_platform_snapshot.dart';
import 'package:mesting_music/shared/media/artwork_refresh_coordinator.dart';

const _netease = PlatformSession(
  userId: 'fixture-a',
  token: 'fixture-a-token',
  platform: MusicPlatform.netease,
);
const _soda = PlatformSession(
  userId: 'fixture-b',
  token: 'fixture-b-token',
  platform: MusicPlatform.qishui,
);

class _Accounts extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _netease;
  void select(PlatformSession? next) => state = AsyncData(next);
}

/// A delayed decoder models a content response arriving before its cover
/// pixels. No public/private service or filesystem participates in this host.
class _ArtworkGate extends ArtworkRefreshCoordinator {
  final requests = <Completer<bool>>[];
  @override
  Future<bool> prepareRefresh(
    Map<String, dynamic> previous,
    Map<String, dynamic> incoming,
  ) {
    final next = Completer<bool>();
    requests.add(next);
    return next.future;
  }
}

void main() {
  testWidgets(
    'platform round trip immediately restores its own shelf and holds replacements for ready artwork',
    (tester) async {
      final artwork = _ArtworkGate();
      final snapshots = PlatformDisplaySnapshots(artwork: artwork);
      final container = ProviderContainer(
        overrides: [
          platformAccountProvider.overrideWith(_Accounts.new),
          platformDisplaySnapshotsProvider.overrideWithValue(snapshots),
        ],
      );
      await container.read(platformAccountProvider.future);
      final content = <MusicPlatform, AsyncValue<String>>{
        MusicPlatform.netease: const AsyncData('cached NetEase'),
        MusicPlatform.qishui: const AsyncLoading(),
      };
      late StateSetter update;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return Consumer(
                  builder: (_, ref, _) {
                    final account = ref.watch(platformAccountProvider).value!;
                    return RetainedPlatformSnapshot<String>(
                      key: ValueKey(account.ownerId),
                      cacheKey: 'home-daily',
                      value: content[account.platform]!,
                      artwork: (value) => [value],
                      loading: () => const Text('loading section'),
                      error: (_, _) => const Text('error section'),
                      data: Text.new,
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
      final accounts =
          container.read(platformAccountProvider.notifier) as _Accounts;
      expect(find.text('cached NetEase'), findsOneWidget);
      accounts.select(_soda);
      await tester.pump();
      expect(find.text('cached NetEase'), findsNothing);
      update(
        () => content[MusicPlatform.qishui] = const AsyncData('cached Soda'),
      );
      await tester.pump();
      expect(find.text('cached Soda'), findsOneWidget);
      update(() => content[MusicPlatform.netease] = const AsyncLoading());
      accounts.select(_netease);
      await tester.pump();
      expect(find.text('cached NetEase'), findsOneWidget);
      expect(find.text('loading section'), findsNothing);
      update(
        () => content[MusicPlatform.netease] = const AsyncData('new NetEase'),
      );
      await tester.pump();
      expect(artwork.requests.length, 1);
      expect(find.text('cached NetEase'), findsOneWidget);
      artwork.requests.single.complete(true);
      await tester.pump();
      await tester.pump();
      expect(find.text('new NetEase'), findsOneWidget);
      update(
        () => content[MusicPlatform.netease] = AsyncError(
          StateError('fixture offline'),
          StackTrace.empty,
        ),
      );
      await tester.pump();
      expect(find.text('new NetEase'), findsOneWidget);
      expect(find.text('error section'), findsNothing);
      accounts.select(_soda);
      update(() => content[MusicPlatform.qishui] = const AsyncLoading());
      await tester.pump();
      expect(find.text('cached Soda'), findsOneWidget);
      expect(find.text('new NetEase'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      snapshots.dispose();
    },
  );

  test(
    'platform changes retain their own snapshots; logout and replacement credentials invalidate them',
    () async {
      final container = ProviderContainer(
        overrides: [platformAccountProvider.overrideWith(_Accounts.new)],
      );
      await container.read(platformAccountProvider.future);
      final snapshots = container.read(platformDisplaySnapshotsProvider);
      snapshots.remember(
        platformDisplayOwner(_netease),
        'home-daily',
        'NetEase only',
        const [],
      );
      final accounts =
          container.read(platformAccountProvider.notifier) as _Accounts;
      accounts.select(_soda);
      await container.pump();
      expect(
        snapshots.read<String>(platformDisplayOwner(_netease), 'home-daily'),
        'NetEase only',
      );
      accounts.select(_netease);
      await container.pump();
      accounts.select(
        const PlatformSession(
          userId: 'fixture-a',
          token: 'replacement',
          platform: MusicPlatform.netease,
        ),
      );
      await container.pump();
      expect(
        snapshots.read<String>(platformDisplayOwner(_netease), 'home-daily'),
        isNull,
      );
      snapshots.remember(
        platformDisplayOwner(_soda),
        'home-daily',
        'Soda only',
        const [],
      );
      accounts.select(_soda);
      await container.pump();
      accounts.select(null);
      await container.pump();
      expect(
        snapshots.read<String>(platformDisplayOwner(_soda), 'home-daily'),
        isNull,
      );
      container.dispose();
    },
  );

  testWidgets(
    'late decoded candidate cannot publish after changing platforms',
    (tester) async {
      final artwork = _ArtworkGate();
      final snapshots = PlatformDisplaySnapshots(artwork: artwork);
      final container = ProviderContainer(
        overrides: [
          platformAccountProvider.overrideWith(_Accounts.new),
          platformDisplaySnapshotsProvider.overrideWithValue(snapshots),
        ],
      );
      await container.read(platformAccountProvider.future);
      var content = const AsyncData<String>('old NetEase');
      late StateSetter update;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return RetainedPlatformSnapshot<String>(
                  cacheKey: 'home-daily',
                  value: content,
                  artwork: (value) => [value],
                  loading: () => const Text('loading'),
                  error: (_, _) => const Text('error'),
                  data: Text.new,
                );
              },
            ),
          ),
        ),
      );
      update(() => content = const AsyncData('late NetEase'));
      await tester.pump();
      (container.read(platformAccountProvider.notifier) as _Accounts).select(
        _soda,
      );
      update(() => content = const AsyncData('Soda'));
      await tester.pump();
      artwork.requests.single.complete(true);
      await tester.pump();
      expect(find.text('Soda'), findsOneWidget);
      expect(find.text('late NetEase'), findsNothing);
      expect(
        snapshots.read<String>(platformDisplayOwner(_netease), 'home-daily'),
        'old NetEase',
      );
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      snapshots.dispose();
    },
  );
}
