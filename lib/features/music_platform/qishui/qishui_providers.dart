import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../../shared/models/track.dart';
import '../../../core/network/music_http_client.dart';
import '../music_platform_providers.dart';
import '../domain/platform_session.dart';
import '../../auth/beta_account_choice.dart';
import 'qishui_api.dart';
import 'qishui_repository.dart';
import 'qishui_session.dart';
import 'qishui_models.dart';
import 'qishui_request_signer.dart';
import 'qishui_signer_settings.dart';
import 'qishui_write_journal.dart';

final qishuiSessionStoreProvider = Provider<QishuiSessionStore>(
  (ref) => const SecureQishuiSessionStore(),
);
final qishuiApiProvider = Provider<QishuiApi>((ref) {
  final client = MusicHttpClient();
  final api = QishuiApi(
    client,
    signer: ConfiguredQishuiRequestSigner(
      client,
      () => ref.read(qishuiSignerSettingsProvider.future),
    ),
    persistRefresh: (expected, updated) => ref
        .read(platformAccountProvider.notifier)
        .persistQishuiRefresh(expected, updated),
  );
  ref.listen(
    qishuiSignerRevisionProvider,
    (previous, next) => api.invalidateSigner(),
  );
  ref.onDispose(() {
    api.dispose();
    client.close();
  });
  return api;
});
final usesQishuiProvider = Provider<bool>(
  (ref) =>
      ref.watch(platformAccountProvider).value?.platform ==
      MusicPlatform.qishui,
);
final qishuiNavigationProvider = Provider<bool>(
  (ref) =>
      ref.watch(usesQishuiProvider) ||
      ref.watch(betaAccountChoiceProvider) == BetaAccountChoice.qishui,
);
final qishuiRepositoryProvider = Provider<QishuiRepository>((ref) {
  ref.watch(
    platformAccountProvider.select((s) => (s.value?.ownerId, s.value?.token)),
  );
  return QishuiRepository(
    ref.watch(qishuiApiProvider),
    writeJournal: QishuiWriteJournal(persistent: true),
  );
});

class QishuiModeController extends Notifier<QishuiFeedMode?> {
  @override
  QishuiFeedMode? build() {
    ref.watch(
      platformAccountProvider.select((v) => (v.value?.ownerId, v.value?.token)),
    );
    return null;
  }

  void select(QishuiFeedMode mode) => state = mode;
}

final qishuiModeProvider =
    NotifierProvider<QishuiModeController, QishuiFeedMode?>(
      QishuiModeController.new,
    );

/// Mode changes cancel old feed requests independently of account requests.
class QishuiFeedScope {
  QishuiFeedScope(this.music, this.mode);
  final QishuiRepository music;
  final QishuiFeedMode? mode;
  final _abort = Completer<void>();
  Future<List<Track>> load() async {
    final result = await music.feed(mode: mode, abortTrigger: _abort.future);
    if (_abort.isCompleted || !music.current) {
      throw const QishuiException('听歌模式或账号已变化');
    }
    return result;
  }

  void dispose() {
    if (!_abort.isCompleted) _abort.complete();
  }
}

final qishuiFeedScopeProvider = Provider<QishuiFeedScope>((ref) {
  final scope = QishuiFeedScope(
    ref.watch(qishuiRepositoryProvider),
    ref.watch(qishuiModeProvider),
  );
  ref.onDispose(scope.dispose);
  return scope;
});
