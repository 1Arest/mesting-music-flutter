import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/cache/cached_browse_provider.dart';

import '../../shared/models/track.dart';
import 'data/platform_artwork.dart';
import 'music_platform_providers.dart';

final platformArtworkRepositoryProvider = Provider<PlatformArtworkRepository>(
  (ref) => PlatformArtworkRepository(ref.watch(musicPlatformApiProvider)),
);

/// Only visible missing/failed images subscribe; listing an entire library
/// never launches a metadata request for every saved song.
final platformArtworkProvider = FutureProvider.autoDispose
    .family<String, Track>(
      (ref, track) => cachedBrowse(
        ref,
        () => ref.watch(platformArtworkRepositoryProvider).resolve(track),
      ),
    );
