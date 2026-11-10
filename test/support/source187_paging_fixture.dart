import 'package:flutter_riverpod/misc.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/source_media_scope.dart';
import 'package:mesting_music/shared/models/track.dart';

class _PagingServer implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:18700');
}

/// Historical paging tests use song157 Kugou records under both platform UIs.
/// Supply their retained login explicitly without opening secure storage or
/// reaching a real source. Playback still verifies every row and page order.
Override retainedPagingLogin187() =>
    sourceMediaScopeProvider(TrackSource.kugou).overrideWith((ref) async {
      final client = MockClient((_) async => throw StateError('No live calls'));
      ref.onDispose(client.close);
      return SourceMediaScope(
        source: TrackSource.kugou,
        api: MusicPlatformApi(server: _PagingServer(), client: client)
          ..session = const PlatformSession(userId: 'paging', token: 'fixture'),
        isCurrent: () => ref.mounted,
      );
    });
