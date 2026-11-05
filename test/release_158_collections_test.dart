import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/data/platform_explore.dart';
import 'package:mesting_music/features/music_platform/data/platform_library_repository.dart';
import 'package:mesting_music/features/music_platform/data/platform_public_playlist.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_collection_play.dart';
import 'release_157_ranking_test.dart' show api157, reply157, owner157;

const playlist158 = PlatformExploreItem(
  id: '3z16o00tpzmz08c',
  title: '合成公开歌单',
  cover: '',
  kind: PlatformExploreKind.playlist,
);
void main() {
  test('public metadata preserves creator identity and unknown counts', () {
    final info = PublicPlaylistInfo.parse(playlist158, {
      'status': 1,
      'data': {
        'info': [
          {
            'global_collection_id': playlist158.id,
            'list_create_userid': 9,
            'list_create_listid': 12,
            'list_create_username': '合成创建者',
            'count': 77,
            'intro': '公开介绍',
          },
        ],
      },
    }, netease: false);
    expect(info.creatorId, '9');
    expect(info.creatorListId, '12');
    expect(info.total, 77);
    expect(info.collections, isNull);
    expect(info.comments, isNull);
  });
  test('NetEase public metadata uses real playlist counts and owner', () {
    final info = PublicPlaylistInfo.parse(playlist158, {
      'playlist': {
        'creator': {'userId': 7, 'nickname': '创建者'},
        'subscribed': true,
        'subscribedCount': 88,
        'commentCount': 9,
        'shareCount': 3,
        'trackCount': 77,
      },
    }, netease: true);
    expect(info.subscribed, isTrue);
    expect(info.collections, 88);
    expect(info.creatorId, '7');
  });
  test(
    'public subscription refers to creator list and manual retry reconciles lost reply',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final rows = <Map<String, dynamic>>[];
      var writes = 0;
      final api = api157((request) async {
        if (request.url.path == '/user/playlist') {
          return reply157({
            'status': 1,
            'data': {'info': rows},
          });
        }
        if (request.url.path == '/playlist/add') {
          writes++;
          expect(request.url.queryParameters['type'], '1');
          expect(
            request.url.queryParameters['list_create_gid'],
            playlist158.id,
          );
          expect(request.url.queryParameters['list_create_userid'], '9');
          if (writes == 1) return reply157({'status': 0, 'error_code': 99});
          rows.add({
            'listid': 81,
            'name': playlist158.title,
            'list_create_gid': playlist158.id,
            'list_create_userid': 9,
            'type': 1,
          });
          throw TimeoutException('synthetic reply loss');
        }
        throw StateError(request.url.path);
      })..session = owner157;
      final repository = PlatformLibraryRepository(
        database,
        api: api,
        identity: owner157,
      );
      addTearDown(repository.dispose);
      Future<void> save() => repository.subscribePublicPlaylist(
        globalId: playlist158.id,
        name: playlist158.title,
        creatorId: '9',
        creatorListId: '12',
        subscribe: true,
      );
      await expectLater(save(), throwsA(anything));
      expect(writes, 1);
      // A known refusal permits a new deliberate request. Its subsequently
      // lost reply is reconciled without a third mutation.
      await expectLater(save(), throwsA(anything));
      // A later call reads authoritative state, never repeats the add mutation.
      await save();
      expect(writes, 2);
      expect(await repository.publicSubscription(playlist158.id), isNotNull);
    },
  );
  test('only the latest explicit card play intent may publish', () {
    final intent = CollectionPlayIntent();
    final first = intent.begin();
    final next = intent.begin();
    expect(intent.owns(first), isFalse);
    expect(intent.owns(next), isTrue);
  });
}
