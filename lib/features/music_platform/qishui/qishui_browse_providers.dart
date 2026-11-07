import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/cache/cached_browse_provider.dart';
import 'qishui_providers.dart';

/// One typed provider per display surface keeps disk hydration and the routed
/// page on the same element. A cache publication refreshes only its consumers.
final qishuiBrowseProvider = FutureProvider.autoDispose.family<Object, String>((
  ref,
  page,
) {
  final music = ref.watch(qishuiRepositoryProvider);
  final abort = Completer<void>();
  ref.onDispose(() {
    if (!abort.isCompleted) abort.complete();
  });
  return cachedBrowse(
    ref,
    () => switch (page) {
      'discover' => music.discover(abortTrigger: abort.future),
      'music' => ref.watch(qishuiFeedScopeProvider).load(),
      'playlists' => music.playlists(abortTrigger: abort.future),
      'history' => music.recent(abortTrigger: abort.future),
      'profile' => music.profile(),
      _ => throw ArgumentError.value(page, 'page'),
    },
  );
}, retry: (_, _) => null);
