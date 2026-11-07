import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_extended_routes.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/platform_capabilities.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/netease-v112-upstream-contracts.json',
            ).readAsStringSync(),
          )
          as Map;
  for (final raw in fixture['cases'] as List) {
    final item = raw as Map;
    test('pinned upstream ${item['route']} ${item['query']}', () {
      final contract = neteaseExtendedRoute(
        '${item['route']}',
        Map<String, Object?>.from(item['query'] as Map),
      );
      expect(contract, isNotNull);
      expect({
        'path': contract!.path,
        'data': contract.data,
        'weapi': contract.weapi,
      }, item['expected']);
    });
  }
  test('unknown protocol routes stay rejected', () {
    expect(neteaseExtendedRoute('/arbitrary/admin/path', {}), isNull);
  });
  test('all Kugou-only capabilities are blocked under NetEase', () {
    for (final feature in PlatformFeature.values) {
      expect(supportsPlatformFeature(MusicPlatform.netease, feature), isFalse);
      expect(supportsPlatformFeature(MusicPlatform.kugou, feature), isTrue);
    }
  });
  test(
    'recent songs unwrap the cloud record instead of becoming blank local rows',
    () async {
      final api = NeteaseApi(
        MockClient(
          (request) async => http.Response(
            jsonEncode({
              'code': 200,
              'data': {
                'list': [
                  {
                    'playTime': 123,
                    'data': {
                      'id': 7,
                      'name': '录音室歌曲',
                      'dt': 240000,
                      'ar': [
                        {'name': '歌手'},
                      ],
                      'al': {'name': '专辑'},
                    },
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      final batch = await NeteaseFeaturesRepository(
        NeteaseMusicRepository(api),
      ).load(NeteaseFeed.recentSongs);
      expect(batch.items.single.track!.id, 'netease_7');
      expect(batch.items.single.track!.duration, const Duration(minutes: 4));
      expect(batch.more, isFalse);
    },
  );
  test(
    'podcast programs use mainSong audio ID and program comment ID separately',
    () {
      final item = NeteaseFeaturesRepository.parse({
        'id': 77,
        'name': '节目',
        'duration': 600000,
        'mainSong': {'id': 88},
        'dj': {'nickname': '主播'},
        'radio': {'name': '播客'},
      }, NeteaseEntity.program);
      expect(item.id, '77');
      expect(item.track!.platformSongId, '88');
      expect(item.track!.externalUrl, contains('program?id=77'));
    },
  );
}
