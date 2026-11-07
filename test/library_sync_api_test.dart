import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/sync/library_sync_models.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/library/data/library_sync_api.dart';

import 'support/test_tracks.dart';

void main() {
  test(
    'cloud library sync authenticates mutations and decodes snapshot',
    () async {
      late Map<String, Object?> requestBody;
      final track = testTracks.first;
      final now = DateTime.utc(2026, 7, 26, 8);
      final api = CloudBaseLibrarySyncApi(
        environmentId: 'music-env',
        sessionProvider: () => AuthSession(
          user: const AuthUser(uid: 'user-1', nickname: 'Mest'),
          accessToken: 'library-access-token',
          refreshToken: 'library-refresh-token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        client: MockClient((request) async {
          expect(request.url.path, '/v1/functions/social-api');
          expect(request.url.queryParameters['webfn'], 'true');
          expect(
            request.headers['authorization'],
            'Bearer library-access-token',
          );
          requestBody = Map<String, Object?>.from(
            jsonDecode(request.body) as Map,
          );
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'snapshot': {
                  'favorites': [
                    {
                      'track': track.toJson(),
                      'created_at': now.toIso8601String(),
                      'updated_at': now.toIso8601String(),
                    },
                  ],
                  'playlists': [
                    {
                      'id': 'playlist-1',
                      'name': '云端歌单',
                      'description': '跨设备保留',
                      'cover_asset': track.coverAsset,
                      'created_at': now.toIso8601String(),
                      'updated_at': now.toIso8601String(),
                      'tracks': [
                        {
                          'track': track.toJson(),
                          'sort_order': 0,
                          'added_at': now.toIso8601String(),
                        },
                      ],
                    },
                  ],
                  'playback_histories': [
                    {
                      'track': track.toJson(),
                      'play_count': 6,
                      'completed_play_count': 4,
                      'total_played_ms': 321000,
                      'last_played_at': now.toIso8601String(),
                    },
                  ],
                  'playback_daily_histories': [
                    {
                      'day_key': '2026-07-26',
                      'track': track.toJson(),
                      'play_count': 2,
                      'total_played_ms': 99000,
                      'last_played_at': now.toIso8601String(),
                    },
                  ],
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final snapshot = await api.synchronize([
        LibrarySyncMutation(
          localId: 7,
          entityType: 'favorite',
          entityId: track.id,
          operation: 'upsert',
          payload: track.toJson(),
          createdAt: now,
        ),
      ]);

      expect(requestBody['action'], 'syncLibrary');
      final mutations = requestBody['mutations']! as List;
      expect((mutations.single as Map)['mutation_id'], 7);
      expect(snapshot.favorites.single.track.id, track.id);
      expect(snapshot.playlists.single.name, '云端歌单');
      expect(snapshot.playlists.single.tracks.single.track.id, track.id);
      expect(snapshot.playbackHistories.single.playCount, 6);
      expect(snapshot.playbackHistories.single.completedPlayCount, 4);
      expect(snapshot.playbackDailyHistories.single.totalPlayedMs, 99000);
    },
  );

  test(
    'cloud library sync keeps local queue retryable on server error',
    () async {
      final api = CloudBaseLibrarySyncApi(
        environmentId: 'music-env',
        sessionProvider: () => AuthSession(
          user: const AuthUser(uid: 'user-1', nickname: 'Mest'),
          accessToken: 'library-access-token',
          refreshToken: 'library-refresh-token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'success': false,
                'code': 'temporarily_unavailable',
                'message': '云端暂时不可用',
              }),
            ),
            503,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );

      await expectLater(
        api.synchronize(const []),
        throwsA(
          isA<LibrarySyncException>().having(
            (error) => error.code,
            'code',
            'temporarily_unavailable',
          ),
        ),
      );
    },
  );

  test('local playlist cover is uploaded before its mutation is sent', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mesting-playlist-cover-sync-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final cover = File('${directory.path}/cover.png');
    await cover.writeAsBytes(const [1, 2, 3, 4]);
    late Map<String, Object?> functionBody;
    final now = DateTime.utc(2026, 7, 26, 12);
    final api = CloudBaseLibrarySyncApi(
      environmentId: 'music-env',
      sessionProvider: () => AuthSession(
        user: const AuthUser(uid: 'user-1', nickname: 'Mest'),
        accessToken: 'library-access-token',
        refreshToken: 'library-refresh-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
      client: MockClient((request) async {
        if (request.url.path == '/v1/storages/get-objects-upload-info') {
          return http.Response(
            jsonEncode([
              {
                'uploadUrl': 'https://upload.example/cover',
                'authorization': 'upload-authorization',
                'token': 'upload-token',
                'cloudObjectMeta': 'upload-meta',
                'cloudObjectId':
                    'cloud://music/user-playlist-covers/user-1/playlist-1/cover.png',
              },
            ]),
            200,
          );
        }
        if (request.url.host == 'upload.example') {
          expect(request.method, 'PUT');
          expect(request.headers['content-type'], 'image/png');
          return http.Response('', 200);
        }
        functionBody = Map<String, Object?>.from(
          jsonDecode(request.body) as Map,
        );
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'success': true,
              'data': {
                'snapshot': {
                  'favorites': [],
                  'playlists': [
                    {
                      'id': 'playlist-1',
                      'name': '云端歌单',
                      'description': '',
                      'cover_asset': 'https://download.example/cover.png',
                      'cover_cloud_id':
                          'cloud://music/user-playlist-covers/user-1/playlist-1/cover.png',
                      'created_at': now.toIso8601String(),
                      'updated_at': now.toIso8601String(),
                      'tracks': [],
                    },
                  ],
                  'playback_histories': [],
                  'playback_daily_histories': [],
                },
              },
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final snapshot = await api.synchronize([
      LibrarySyncMutation(
        localId: 9,
        entityType: 'playlist',
        entityId: 'playlist-1',
        operation: 'upsert',
        payload: {
          'id': 'playlist-1',
          'name': '云端歌单',
          'cover_asset': cover.path,
          'cover_cloud_id': null,
        },
        createdAt: now,
      ),
    ]);

    final mutation = (functionBody['mutations']! as List).single as Map;
    final payload = mutation['payload']! as Map;
    expect(payload['cover_asset'], isNull);
    expect(payload['cover_cloud_id'], startsWith('cloud://music/'));
    expect(snapshot.playlists.single.coverAsset, contains('download.example'));
    expect(snapshot.playlists.single.coverCloudId, startsWith('cloud://'));
  });
}
