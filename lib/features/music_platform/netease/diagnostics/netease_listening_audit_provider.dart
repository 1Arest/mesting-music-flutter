import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../library/library_providers.dart';
import '../../listening_sync/listening_sync_store.dart';
import '../../music_platform_providers.dart';
import '../../platform_backend_providers.dart';
import 'netease_listening_audit.dart';

/// One consistent local read snapshot per deliberate load. No music-platform
/// API, phone bridge, clipboard, replay or background upload is used here.
final neteaseListeningAuditProvider = FutureProvider.autoDispose
    .family<NeteaseListeningAudit, String>((ref, month) async {
      final account = ref.watch(platformAccountProvider).value;
      if (!ref.watch(usesNeteaseProvider) || account == null) {
        throw StateError('请先选择网易云账号');
      }
      final database = ref.watch(appDatabaseProvider), owner = account.ownerId;
      final report = await database.transaction(() async {
        final days = await (database.select(
          database.playbackDailyHistories,
        )..where((row) => row.ownerId.equals(owner))).get();
        final entries = await ListeningSyncStore(database).entries(owner);
        return NeteaseListeningAudit.build(
          owner: owner,
          month: month,
          now: DateTime.now(),
          entries: entries,
          days: days.map(
            (d) => ListeningAuditDay(
              owner: d.ownerId,
              day: d.dayKey,
              songId: d.trackId,
              milliseconds: d.totalPlayedMs,
              neteaseSong: RegExp(r'^netease_\d+$').hasMatch(d.trackId),
            ),
          ),
        );
      });
      if (!ref.mounted ||
          ref.read(platformAccountProvider).value?.ownerId != owner) {
        throw StateError('账号已变化，请重新读取诊断');
      }
      return report;
    }, retry: (_, _) => null);
