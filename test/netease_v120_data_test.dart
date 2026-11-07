import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_message_counts.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/shared/media/persistent_network_image_cache.dart';
import 'package:mesting_music/shared/utils/media_uri.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'the observed unread envelope includes private messages and new followers',
    () {
      expect(
        parseNeteaseMessageCounts({
          'code': 200,
          'msg': 170,
          'comment': 3,
          'notice': 2,
          'forward': 1,
          'follow': 4,
          'event': 600,
        }),
        {
          'privateMsgCount': 170,
          'commentCount': 3,
          'noticeCount': 2,
          'forwardCount': 1,
          'newFollowerCount': 4,
        },
      );
    },
  );
  test(
    'public CDN requests identify the app without leaking credentials to other hosts',
    () {
      expect(artworkRequestHeaders('https://p1.music.126.net/a.jpg'), const {
        'User-Agent': 'MestingMusic/1.0 (Artwork)',
      });
      expect(
        artworkRequestHeaders('https://music.126.net.example/a.jpg'),
        isNull,
      );
      expect(
        artworkRequestHeaders('https://other.example/a.jpg?signature=x'),
        isNull,
      );
    },
  );
  test('short numeric unread fields and nested counts retain real values', () {
    expect(
      parseNeteaseMessageCounts({
        'code': 200,
        'data': {
          'privateMsg': '28',
          'commentCount': 3,
          'notice': 2,
          'forward': 1,
        },
      }),
      {
        'privateMsgCount': 28,
        'commentCount': 3,
        'noticeCount': 2,
        'forwardCount': 1,
      },
    );
    expect(
      parseNeteaseMessageCounts({'privateMsgCount': 0, 'privateCount': '28'}),
      {'privateMsgCount': 28},
    );
  });
  test(
    'unknown envelope and unrelated account numbers cannot become unread zero',
    () {
      expect(
        () => parseNeteaseMessageCounts({
          'code': 200,
          'data': {'userId': 28, 'level': 9},
        }),
        throwsFormatException,
      );
      expect(
        () => parseNeteaseMessageCounts({'privateMsgCount': false}),
        throwsFormatException,
      );
      expect(parseNeteaseMessageCounts({'privateMsgCount': '0'}), {
        'privateMsgCount': 0,
      });
    },
  );
  test(
    'negative unread values are bounded without turning dates into counts',
    () {
      expect(
        parseNeteaseMessageCounts({
          'privateCount': -4,
          'commentCount': '5',
          'time': 700000,
        }),
        {'privateMsgCount': 0, 'commentCount': 5},
      );
    },
  );
  test(
    '28 unread conversations survive missing totals, then reading clears only those messages',
    () async {
      var newest = 1000;
      var unread = 28;
      final api =
          NeteaseApi(
            MockClient(
              (request) async => http.Response(
                jsonEncode({
                  'code': 200,
                  if (request.url.path.endsWith('/private/users'))
                    'msgs': [
                      {
                        'lastMsgTime': newest,
                        'newMsgCount': unread,
                        'lastMsg': jsonEncode({'msg': 'fixture'}),
                        'fromUser': {'userId': 8},
                        'toUser': {'userId': 7},
                      },
                    ],
                }),
                200,
              ),
            ),
          )..configure(
            const NeteaseSession(
              userId: '7',
              cookies: {'MUSIC_U': 'fixture'},
              deviceId: 'fixture',
            ),
          );
      final repo = NeteaseMessagesRepository(NeteaseMusicRepository(api));
      addTearDown(repo.dispose);
      await repo.conversations();
      await expectLater(repo.counts(), throwsFormatException);
      expect(repo.visibleCounts({})['privateMsgCount'], 28);
      expect(repo.visibleCounts({'privateMsgCount': 0})['privateMsgCount'], 28);
      expect(
        repo.visibleCounts({'privateMsgCount': 35})['privateMsgCount'],
        35,
      );
      repo.reads.displayed('8', DateTime.fromMillisecondsSinceEpoch(newest));
      expect(repo.visibleCounts({})['privateMsgCount'], 0);
      expect(repo.visibleCounts({'privateMsgCount': 35})['privateMsgCount'], 7);
      newest = 2000;
      unread = 1;
      await repo.conversations();
      expect(repo.visibleCounts({})['privateMsgCount'], 1);
    },
  );
  test(
    'an invalid nonempty old disk entry is replaced by an actual image response',
    () async {
      final root = await Directory.systemTemp.createTemp('mesting120-cache-');
      addTearDown(() => root.delete(recursive: true));
      var requests = 0;
      final client = MockClient((request) async {
        expect(request.headers['User-Agent'], 'MestingMusic/1.0 (Artwork)');
        requests++;
        return http.Response.bytes([255, 216, 255, 0], 200);
      });
      final first = PersistentNetworkImageCache(
        client: client,
        directoryProvider: () async => root,
      );
      const url = 'https://p1.music.126.net/fixture.jpg?param=192y192';
      final file = await first.resolve(cacheKey: 'playlist', url: url);
      expect(file, isNotNull);
      await file!.writeAsString('<html>cached error</html>');
      final restarted = PersistentNetworkImageCache(
        client: client,
        directoryProvider: () async => root,
      );
      final corrected = await restarted.resolve(cacheKey: 'playlist', url: url);
      expect(corrected, isNotNull);
      expect(requests, 2);
      expect(await corrected!.readAsBytes(), [255, 216, 255, 0]);
    },
  );
}
