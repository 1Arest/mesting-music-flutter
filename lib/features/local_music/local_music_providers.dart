import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/local_music_repository.dart';
import 'domain/local_music.dart';

final localMusicRepositoryProvider = Provider<LocalMusicRepository>(
  (ref) => const AndroidLocalMusicRepository(),
);

class LocalMusicState {
  const LocalMusicState({
    this.library = const LocalMusicLibrary(),
    this.loading = false,
    this.busy = false,
    this.error = '',
    this.errorCode = '',
  });
  final LocalMusicLibrary library;
  final bool loading, busy;
  final String error, errorCode;
}

final localMusicControllerProvider =
    NotifierProvider<LocalMusicController, LocalMusicState>(
      LocalMusicController.new,
    );

/// Serial UI commands keep a picker result from racing a scan/removal. The
/// native side separately enforces this contract for non-UI callers.
class LocalMusicController extends Notifier<LocalMusicState> {
  @override
  LocalMusicState build() {
    unawaited(
      Future<void>.microtask(() async {
        if (ref.mounted) await load();
      }),
    );
    return const LocalMusicState(loading: true);
  }

  Future<void> _run(
    Future<LocalMusicLibrary> Function(LocalMusicRepository) command,
  ) async {
    if (!ref.mounted || state.busy) return;
    state = LocalMusicState(library: state.library, busy: true);
    try {
      final result = await command(ref.read(localMusicRepositoryProvider));
      if (!ref.mounted) return;
      state = LocalMusicState(library: result);
    } on Object catch (error) {
      if (!ref.mounted) return;
      state = LocalMusicState(
        library: state.library,
        error: error is LocalMusicException ? error.message : '本地音乐操作未完成，请重试',
        errorCode: error is LocalMusicException ? error.code : '',
      );
    }
  }

  Future<void> load() => _run((repository) => repository.load());
  Future<void> scan() => _run((repository) => repository.scan());
  Future<void> importFiles() => _run((repository) => repository.importFiles());
  Future<void> importDirectory() =>
      _run((repository) => repository.importDirectory());
  Future<void> refresh() => _run((repository) => repository.refresh());
  Future<void> remove(String id) => _run((repository) => repository.remove(id));

  void markUnavailable(String id) {
    state = LocalMusicState(
      library: LocalMusicLibrary(
        entries: [
          for (final entry in state.library.entries)
            entry.id == id ? entry.withAvailability(false) : entry,
        ],
        permissionGranted: state.library.permissionGranted,
        notice: state.library.notice,
      ),
      busy: state.busy,
    );
  }
}

final localMusicArtworkProvider = FutureProvider.autoDispose
    .family<String, String>(
      (ref, id) async => ref.watch(localMusicRepositoryProvider).artwork(id),
    );
