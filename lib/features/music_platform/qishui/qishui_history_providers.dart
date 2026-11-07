import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_providers.dart';
import '../music_platform_providers.dart';
import 'qishui_history_reporter.dart';
import 'qishui_history_repository.dart';
import 'qishui_providers.dart';
import 'qishui_write_journal.dart';

class QishuiHistoryStatusController extends Notifier<QishuiHistorySyncStatus> {
  @override
  QishuiHistorySyncStatus build() {
    ref.watch(
      platformAccountProvider.select((s) => (s.value?.ownerId, s.value?.token)),
    );
    return const QishuiHistorySyncStatus();
  }

  void update(QishuiHistorySyncStatus value) => state = value;
}

final qishuiHistoryStatusProvider =
    NotifierProvider<QishuiHistoryStatusController, QishuiHistorySyncStatus>(
      QishuiHistoryStatusController.new,
    );

/// Keep this provider watched by the Beta application host. It owns one
/// subscription for the active Soda credential and disposes it on switching.
/// No network starts until a new, genuinely consumed playback event arrives.
final qishuiHistorySyncProvider = Provider<void>((ref) {
  if (!ref.watch(usesQishuiProvider)) return;
  final music = ref.watch(qishuiRepositoryProvider);
  if (!music.current) return;
  final handler = ref.watch(audioHandlerProvider);
  final entryRevision = handler.transportRevision;
  final history = QishuiHistoryRepository(
    call: music.call,
    current: () => music.current,
    owner: music.api.session!.userId,
    journal: QishuiWriteJournal(persistent: true),
  );
  final reporter = QishuiHistoryReporter(
    history: history,
    onStatus: (status) =>
        ref.read(qishuiHistoryStatusProvider.notifier).update(status),
  );
  final subscription = handler.consumedTrackStream.listen((track) {
    // A queued event from the outgoing account can arrive after a new
    // subscription is installed. Only a new transport occurrence owned by
    // this binding, still naming the current track, may create cloud history.
    if (handler.transportRevision <= entryRevision ||
        handler.mediaItem.value?.id != track.id ||
        !music.current) {
      return;
    }
    unawaited(
      reporter.confirmPlayed(
        track,
        playbackRevision: handler.transportRevision,
      ),
    );
  });
  ref.onDispose(() {
    reporter.dispose();
    unawaited(subscription.cancel());
  });
});
