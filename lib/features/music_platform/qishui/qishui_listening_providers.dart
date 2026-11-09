import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'qishui_listening_repository.dart';
import 'qishui_providers.dart';
import 'qishui_listening_reporter.dart';

/// Repository lifetime follows the captured account and credential. Loading
/// the UI never starts playback reporting; the application binding owns that
/// separate subscription and only reports genuinely consumed intervals.
final qishuiListeningRepositoryProvider = Provider<QishuiListeningRepository>((
  ref,
) {
  final music = ref.watch(qishuiRepositoryProvider);
  final repository = QishuiListeningRepository(
    api: music.api,
    current: () => music.current,
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final qishuiOfficialListeningProvider = FutureProvider<QishuiListeningSnapshot>(
  (ref) {
    final abort = Completer<void>();
    ref.onDispose(() {
      if (!abort.isCompleted) abort.complete();
    });
    return ref
        .watch(qishuiListeningRepositoryProvider)
        .fetch(abortTrigger: abort.future);
  },
  // Business/signature errors require the user's explicit refresh. Riverpod's
  // default retry timer must not repeatedly dispatch unsupported account reads.
  retry: (count, error) => null,
);

class QishuiListeningStatusController extends Notifier<QishuiListeningStatus> {
  @override
  QishuiListeningStatus build() {
    ref.watch(qishuiRepositoryProvider);
    return const QishuiListeningStatus();
  }

  void update(QishuiListeningStatus value) => state = value;
}

final qishuiListeningStatusProvider =
    NotifierProvider<QishuiListeningStatusController, QishuiListeningStatus>(
      QishuiListeningStatusController.new,
    );

final qishuiListeningLedgerProvider = FutureProvider<QishuiListeningLedger>((
  ref,
) {
  // Re-read only after a settled submission, not on every playback second.
  ref.watch(
    qishuiListeningStatusProvider.select(
      (value) =>
          (value.transportAcceptedMilliseconds, value.unconfirmedMilliseconds),
    ),
  );
  return ref.watch(qishuiListeningRepositoryProvider).ledger();
}, retry: (count, error) => null);

String qishuiListeningLabel(int? seconds) {
  if (seconds == null) return '—';
  final time = Duration(seconds: seconds);
  if (time.inHours > 0) {
    return '${time.inHours}小时${time.inMinutes.remainder(60)}分';
  }
  return '${time.inMinutes}分${time.inSeconds.remainder(60)}秒';
}
