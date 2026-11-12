import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mesting_music/core/database/app_database.dart';

import '../test/support/test_tracks.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android 数据库原子切换收藏并按账号隔离', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final track = testTracks[1];

    expect(await database.toggleFavorite('user-a', track), isTrue);
    expect(await database.isFavorite('user-a', track.id), isTrue);
    expect(await database.isFavorite('user-b', track.id), isFalse);
    expect(await database.toggleFavorite('user-a', track), isFalse);
    expect(await database.isFavorite('user-a', track.id), isFalse);

    for (var index = 0; index < 20; index += 1) {
      await database.toggleFavorite('user-a', track);
    }
    expect(await database.isFavorite('user-a', track.id), isFalse);

    await database.savePlaybackSession(
      ownerId: 'user-a',
      queue: [track],
      currentIndex: 0,
      position: const Duration(seconds: 18),
      playbackMode: 'list',
    );
    expect(await database.loadPlaybackSession('user-b'), isNull);
    expect((await database.loadPlaybackSession('user-a'))?.positionMs, 18000);

    await database.recordPlayback('user-a', track, Duration.zero);
    expect(await database.watchPlaybackHistory('user-b').first, isEmpty);
    expect(
      (await database.watchPlaybackHistory('user-a').first).single.trackId,
      track.id,
    );
  });
}
