import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/track.dart';
import 'source_media_scope.dart';
import 'data/linked_music_recordings.dart';
import 'data/platform_search_repository.dart';
import 'netease/netease_catalog_adapters.dart';
import 'data/linked_music_mvs.dart';
import 'data/platform_mv_repository.dart';
import 'netease/netease_mv_repository.dart';

final linkedMusicRecordingsProvider = FutureProvider.autoDispose
    .family<LinkedMusicRecordings, Track>((ref, track) async {
      final values = await linkMusicRecordings(track, (source) async {
        final scope = await ref.watch(sourceMediaScopeProvider(source).future);
        return scope.music != null
            ? NeteaseSearchAdapter(scope.api, scope.music!)
            : PlatformSearchRepository(scope.api);
      });
      if (!ref.mounted) throw StateError('来源已变化');
      return values;
    }, retry: (_, _) => null);

final linkedMvSourceProvider =
    FutureProvider.family<MvSourceRepositories, TrackSource>((
      ref,
      source,
    ) async {
      final scope = await ref.watch(sourceMediaScopeProvider(source).future);
      return MvSourceRepositories(
        scope.music != null
            ? NeteaseMvRepository(scope.api, scope.music!)
            : PlatformMvRepository(scope.api),
        scope.music != null
            ? NeteaseSearchAdapter(scope.api, scope.music!)
            : PlatformSearchRepository(scope.api),
        scope.isCurrent,
      );
    }, retry: (_, _) => null);
