import '../../../core/network/system_music_io_client.dart';
import '../domain/platform_session.dart';
import '../domain/kugou_listening_profile.dart';
import '../kugou_listening_profile_providers.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../core/persistence/app_preferences.dart';
import '../../../core/persistence/playback_persistence_controller.dart';
import '../../library/library_providers.dart';
import '../music_platform_providers.dart';
import '../data/kugou_official_api.dart';
import '../data/kugou_v4_grade_repository.dart';
import 'listening_sync_coordinator.dart';
import 'listening_daily_readback.dart';
import 'listening_sync_models.dart';
import 'listening_sync_repository.dart';
import 'listening_sync_store.dart';

final platformListeningSyncEnabledProvider =
    NotifierProvider<ListeningSyncEnabled, bool>(ListeningSyncEnabled.new);

class ListeningSyncEnabled extends Notifier<bool> {
  static const preferenceKey = 'kugou_listening_cloud_sync_v1';
  @override
  bool build() =>
      ref.read(sharedPreferencesProvider).getBool(preferenceKey) ?? true;

  Future<void> setEnabled(bool enabled) async {
    // Persist before publishing the toggle, so a storage failure is visible to
    // the settings caller and cannot silently change the next launch's policy.
    final saved = await ref
        .read(sharedPreferencesProvider)
        .setBool(preferenceKey, enabled);
    if (!saved) throw StateError('同步设置暂未保存，请重试');
    state = enabled;
  }
}

final platformListeningSyncStoreProvider = Provider<ListeningSyncStore>(
  (ref) => ListeningSyncStore(ref.watch(appDatabaseProvider)),
);

/// Standard grade authorization is separate from the legacy playback login.
/// Closing this account epoch also invalidates A→B→A late network responses.
final kugouV4GradeRepositoryProvider = Provider<KugouV4GradeRepository>((ref) {
  ref.watch(
    platformAccountProvider.select(
      (value) => (
        value.value?.platform,
        value.value?.userId,
        value.value?.token,
        value.value?.kugouStandardToken,
      ),
    ),
  );
  final api = ref.watch(musicPlatformApiProvider);
  final client = SystemMusicIoClient();
  var closed = false;
  ref.listen(platformAccountProvider, (previous, next) {
    final before = previous?.value, after = next.value;
    if (before?.platform != after?.platform ||
        before?.userId != after?.userId ||
        before?.token != after?.token ||
        before?.kugouStandardToken != after?.kugouStandardToken) {
      // 同步撤销旧授权周期，快速A→B→A也不能让旧请求重新有效。
      closed = true;
      client.close();
    }
  });
  ref.onDispose(() {
    closed = true;
    client.close();
  });
  return KugouV4GradeRepository(
    client: client,
    currentIdentity: () =>
        closed ? null : ref.read(platformAccountProvider).value,
    device: () => KugouOfficialApi.registeredDevice(api),
    clock: ref.watch(kugouListeningProfileClockProvider),
  );
});

/// Watch once from the Beta application root. Rebuilds/route changes do not
/// create more subscriptions; account and toggle listeners drive activation.
final platformListeningSyncProvider = Provider<ListeningSyncCoordinator>((ref) {
  final api = ref.watch(musicPlatformApiProvider);
  final coordinator = ListeningSyncCoordinator(
    feed: HandlerListeningAudioFeed(ref.watch(audioHandlerProvider)),
    store: ref.watch(platformListeningSyncStoreProvider),
    gateway: KugouListeningRepository(api),
    standardGradeGateway: ref.watch(kugouV4GradeRepositoryProvider),
    currentIdentity: () => api.session,
    officialDayReader: (identity, day) async {
      final fact = await ref
          .read(kugouListeningProfileRepositoryProvider)
          .statistics(identity, KugouListenPeriod.day, day);
      final seconds = fact.seconds;
      if (seconds == null) {
        throw const FormatException('Official daily duration is absent');
      }
      final reader = ref.read(kugouListeningProfileReaderProvider);
      if (reader?.belongsTo(identity) == true) {
        reader!.acceptStatistics(fact);
        // Read-back refreshes shared snapshots without replaying uploads or
        // waiting for network/profile work on the audio event thread.
        unawaited(reader.refreshCurrentStatistics());
      }
      return OfficialListeningDayFact(
        day: fact.date,
        seconds: seconds,
        readAt: fact.readAt,
        totalSeconds: fact.totalSeconds,
      );
    },
    prepareOwner: ref
        .watch(playbackPersistenceControllerProvider)
        .activateOwner,
  );
  void activate() => unawaited(
    coordinator.activate(
      // This coordinator uploads only Kugou counters. Other platform accounts
      // must not acquire its worker or create pending Kugou report records.
      ref.read(platformAccountProvider).value?.platform == MusicPlatform.kugou
          ? ref.read(platformAccountProvider).value
          : null,
      enabled: ref.read(platformListeningSyncEnabledProvider),
    ),
  );
  ref.listen(platformAccountProvider, (previous, next) {
    final before = previous?.value;
    final after = next.value;
    // Profile metadata changes keep the same authentication epoch. They
    // must not manufacture another play instance or split a listening span.
    if (previous != null &&
        before?.ownerId == after?.ownerId &&
        before?.token == after?.token &&
        before?.kugouStandardToken == after?.kugouStandardToken) {
      return;
    }
    activate();
  }, fireImmediately: true);
  ref.listen(platformListeningSyncEnabledProvider, (_, _) => activate());
  ref.onDispose(() => unawaited(coordinator.dispose()));
  return coordinator;
});

final platformListeningSyncSummaryProvider =
    StreamProvider<ListeningSyncSummary>((ref) {
      final session = ref.watch(platformAccountProvider).value;
      if (session == null || session.platform != MusicPlatform.kugou) {
        return Stream.value(ListeningSyncSummary(const []));
      }
      return ref
          .watch(platformListeningSyncStoreProvider)
          .watchSummary('kugou:${session.userId}');
    });

/// The value belongs to the current account and current calendar day. It is a
/// read-back observation, separate from accepted/uncertain upload counts.
final kugouOfficialDailySyncStatusProvider =
    StreamProvider<OfficialListeningDayStatus?>((ref) {
      final session = ref.watch(platformAccountProvider).value;
      final clock = ref.watch(kugouListeningProfileClockProvider);
      if (session == null || session.platform != MusicPlatform.kugou) {
        return Stream.value(null);
      }
      return ref
          .watch(platformListeningSyncStoreProvider)
          .watchOfficialDays('kugou:${session.userId}')
          .map((rows) {
            final day = OfficialListeningDayStatus.dayKey(clock());
            for (final row in rows) {
              final value = OfficialListeningDayStatus.fromEntry(row);
              if (value?.day == day) return value;
            }
            return null;
          });
    });
