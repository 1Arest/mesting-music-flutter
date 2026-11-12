import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_record.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_records_repository.dart';

// Synthetic public-schema fixtures, not an account capture. Field names and
// endpoint-specific units come from the actual official render call sites:
// ending QmAe.e reads seconds; list QmAe.c reads milliseconds. The v140
// contract had mistaken the list helper for the ending helper; see the v142
// correction and official-record-{list,ending}.js
// in the private v140 investigation directory. Transport tests verify Mesting's
// existing EAPI adapter; they do not prove equality to the official bridge's
// hidden wire transport or acceptance by a real account.
const _session = NeteaseSession(
  userId: '7',
  deviceId: 'fixture',
  nickname: '本人',
  avatarUrl: 'https://p1.music.126.net/self.jpg',
  cookies: {'MUSIC_U': 'fixture'},
);
const _room = 'synthetic_room_1793619000000';
const _report = {
  'userInfo': {'userId': 8},
  'anotherUserInfo': {'userId': 7},
  'duration': 93900,
  'songCount': 224,
  'totalDuration': 56909760,
  'totalSongCount': 18344,
  'distance': 3167.77,
  'endTime': 1793619000000,
  'roomType': 'FRIEND',
  'scene': 'MOBILE_FRIEND',
  'online': false,
  'canInvite': true,
  'showCollectBtn': true,
};
const _history = {
  'records': [
    {
      'id': 'record-1',
      'date': '昨天',
      'startTime': 1793523900000,
      'userId': 8,
      'nick': '好友',
      'avatar': 'https://p1.music.126.net/friend.jpg',
      'duration': 93900000,
      'totalSong': 224,
      'roomId': _room,
      'ltType': 1,
      'recordRoomType': 'friend_room',
      'online': false,
      'canInvite': true,
    },
  ],
  'mostListen': {
    'selfAvatar': 'https://p1.music.126.net/self-most.jpg',
    'friendAvatar': 'https://p1.music.126.net/friend-most.jpg',
    'friendNick': '最常一起听的好友',
    'friendUid': 8,
    'totalDuration': 56909760000,
    'totalSong': 18344,
    'ltType': 1,
    'online': false,
  },
  'hasMore': true,
  'nextCursor': 'opaque:next+cursor/=',
  'vip': false,
  'vipType': 0,
};

Map<String, dynamic> _decodeEapi(http.Request request) {
  final hex = request.bodyFields['params']!;
  final cipher = PaddedBlockCipher('AES/ECB/PKCS7')
    ..init(
      false,
      PaddedBlockCipherParameters(
        KeyParameter(Uint8List.fromList(utf8.encode('e82ckenh8dichen8'))),
        null,
      ),
    );
  final bytes = Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
  final parts = utf8.decode(cipher.process(bytes)).split('-36cd479b6b5-');
  expect(parts.first, request.url.path.replaceFirst('/eapi/', '/api/'));
  return Map<String, dynamic>.from(jsonDecode(parts[1]) as Map);
}

http.Response _reply(Object? data) => http.Response(
  jsonEncode({'code': 200, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'ending report keeps second durations and kilometres without live-clock substitution',
    () {
      final value = NeteaseTogetherRecord.fromReport(
        _report,
        roomId: _room,
        selfId: '7',
        peerId: '8',
      );
      expect(value.self?.id, '7');
      expect(value.peer?.id, '8');
      expect(value.duration, const Duration(hours: 26, minutes: 5));
      expect(value.totalDuration, const Duration(hours: 15808, minutes: 16));
      expect(value.songCount, 224);
      expect(value.totalSongCount, 18344);
      expect(value.distanceKilometres, 3167.77);
      expect(value.endedAt!.millisecondsSinceEpoch, 1793619000000);
      expect(value.startedAt, isNull);
      expect(value.songIds, isNull);
    },
  );

  test(
    'missing and malformed report measurements remain unknown, explicit zero remains zero',
    () {
      final unknown = NeteaseTogetherRecord.fromReport(
        {
          'userInfo': {'userId': 7},
          'anotherUserInfo': {'userId': 8},
          'duration': -1,
          'totalDuration': 'bad',
          'songCount': -1,
          'distance': 'NaN',
          // Existing live-room values are deliberately not report aliases.
          'currentConnectionTime': 999,
          'totalConnectionTime': 9999,
        },
        roomId: _room,
        selfId: '7',
      );
      expect(unknown.duration, isNull);
      expect(unknown.totalDuration, isNull);
      expect(unknown.songCount, isNull);
      expect(unknown.totalSongCount, isNull);
      expect(unknown.distanceKilometres, isNull);
      final zero = NeteaseTogetherRecord.fromReport(
        {'duration': 0, 'totalDuration': '0', 'songCount': 0, 'distance': 0},
        roomId: _room,
        selfId: '7',
      );
      expect(zero.duration, Duration.zero);
      expect(zero.totalDuration, Duration.zero);
      expect(zero.songCount, 0);
      expect(zero.distanceKilometres, 0);
    },
  );

  test(
    'history and most-listened use their distinct actual schemas and preserve cursor and VIP limits',
    () {
      final value = NeteaseTogetherHistoryPageData.fromJson(
        _history,
        self: const NeteaseTogetherProfile(id: '7', name: '本人'),
      );
      expect(value.records.single.dateLabel, '昨天');
      expect(
        value.records.single.duration,
        const Duration(hours: 26, minutes: 5),
      );
      expect(value.records.single.songCount, 224);
      expect(value.records.single.peer?.name, '好友');
      expect(value.records.single.roomType, 'FRIEND');
      expect(value.records.single.scene, 'MOBILE_FRIEND');
      expect(value.mostListened!.peer?.id, '8');
      expect(value.mostListened!.peer?.name, '最常一起听的好友');
      expect(value.mostListened!.totalSongCount, 18344);
      expect(
        value.mostListened!.totalDuration,
        const Duration(hours: 15808, minutes: 16),
      );
      expect(value.mostListened!.duration, isNull);
      expect(value.mostListened!.roomId, isEmpty);
      expect(value.nextCursor, 'opaque:next+cursor/=');
      expect(value.hasMore, true);
      expect(value.membershipLimited, true);
      expect(() => value.records.clear(), throwsUnsupportedError);
    },
  );

  test(
    'a missing history cursor or membership boundary is not manufactured',
    () {
      final value = NeteaseTogetherHistoryPageData.fromJson({'records': []});
      expect(value.records, isEmpty);
      expect(value.mostListened, isNull);
      expect(value.hasMore, isNull);
      expect(value.nextCursor, isNull);
      expect(value.vip, isNull);
    },
  );

  test(
    'multi-room rows retain their distinct identity and unknown ordinary-room type',
    () {
      final value = NeteaseTogetherRecord.fromHistory({
        'roomId': 'multi_synthetic',
        'recordRoomType': 'multi_room',
        'targetUrl':
            'https://st.music.163.com/multi_room/result?roomId=multi_synthetic',
        'date': '10-31',
      });
      expect(value.isMultiRoom, true);
      expect(value.roomType, isNull);
      expect(value.scene, isNull);
      expect(value.dateLabel, '10-31');
      expect(value.officialUrl?.scheme, 'https');
      expect(
        NeteaseTogetherRecord.fromHistory({
          'targetUrl': 'https://evil.invalid/',
        }).officialUrl,
        isNull,
      );
    },
  );

  test(
    'history reads exactly one encrypted page with the supplied opaque cursor',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.method, 'POST');
        expect(request.url.host, 'interface.music.163.com');
        expect(request.url.path, '/eapi/listen/together/full/records');
        final payload = _decodeEapi(request);
        expect(payload['page'], {
          'size': 50,
          'cursor': requests.length == 1 ? '' : 'opaque:next+cursor/=',
        });
        expect(payload.keys.toSet(), {'page', 'header', 'e_r'});
        return _reply(_history);
      });
      addTearDown(client.close);
      final api = NeteaseApi(client)..configure(_session);
      final repository = NeteaseTogetherRecordsRepository(
        NeteaseMusicRepository(api),
      );
      final first = await repository.history();
      await repository.history(cursor: first.nextCursor);
      expect(requests.length, 2);
      expect(first.records.single.self?.id, '7');
    },
  );

  test(
    'report obtains public display profiles after reading actual participant IDs',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/eapi/listen/together/record/get') {
          final body = _decodeEapi(request);
          expect(body['roomId'], _room);
          expect(body.keys.toSet(), {'roomId', 'header', 'e_r'});
          return _reply(_report);
        }
        final id = request.url.path.split('/').last;
        expect(request.url.path, '/weapi/v1/user/detail/$id');
        return http.Response(
          jsonEncode({
            'code': 200,
            'profile': {
              'userId': int.parse(id),
              'nickname': '用户$id',
              'avatarUrl': 'https://p1.music.126.net/$id.jpg',
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      addTearDown(client.close);
      final api = NeteaseApi(client)..configure(_session);
      final value = await NeteaseTogetherRecordsRepository(
        NeteaseMusicRepository(api),
      ).report(_room, peerId: '8');
      expect(value.self?.name, '用户7');
      expect(value.peer?.name, '用户8');
      expect(value.duration, const Duration(hours: 26, minutes: 5));
      expect(paths.toSet(), {
        '/eapi/listen/together/record/get',
        '/weapi/v1/user/detail/7',
        '/weapi/v1/user/detail/8',
      });
      expect(paths.length, 3);
      expect(paths.any((path) => path.contains('room/songs')), false);
    },
  );

  test(
    'optional profile failures keep valid server report statistics',
    () async {
      final client = MockClient(
        (request) async =>
            request.url.path == '/eapi/listen/together/record/get'
            ? _reply(_report)
            : http.Response('{"code":500}', 200),
      );
      addTearDown(client.close);
      final api = NeteaseApi(client)..configure(_session);
      final value = await NeteaseTogetherRecordsRepository(
        NeteaseMusicRepository(api),
      ).report(_room);
      expect(value.peer?.id, '8');
      expect(value.peer?.name, isEmpty);
      expect(value.songCount, 224);
    },
  );

  test(
    'song IDs come only from the separate explicit read and remain immutable',
    () async {
      var count = 0;
      final client = MockClient((request) async {
        count++;
        expect(request.url.path, '/eapi/listen/together/room/songs/list');
        expect(_decodeEapi(request)['roomId'], _room);
        return _reply({
          'songIds': [101, '102', 101, '../bad'],
        });
      });
      addTearDown(client.close);
      final api = NeteaseApi(client)..configure(_session);
      final ids = await NeteaseTogetherRecordsRepository(
        NeteaseMusicRepository(api),
      ).songIds(_room);
      expect(ids, ['101', '102']);
      expect(() => ids.add('103'), throwsUnsupportedError);
      expect(count, 1);
    },
  );

  test('a report cannot silently describe a different friend', () async {
    var count = 0;
    final client = MockClient((_) async {
      count++;
      return _reply(_report);
    });
    addTearDown(client.close);
    final api = NeteaseApi(client)..configure(_session);
    final repository = NeteaseTogetherRecordsRepository(
      NeteaseMusicRepository(api),
    );
    await expectLater(repository.report(_room, peerId: '99'), throwsException);
    expect(count, 1);
  });

  test('invalid room IDs are rejected before any request', () async {
    var count = 0;
    final client = MockClient((_) async {
      count++;
      return _reply(_report);
    });
    addTearDown(client.close);
    final api = NeteaseApi(client)..configure(_session);
    final repository = NeteaseTogetherRecordsRepository(
      NeteaseMusicRepository(api),
    );
    for (final room in ['', '../room', 'room?userId=9', 'room/other']) {
      await expectLater(repository.report(room), throwsException);
    }
    expect(count, 0);
  });

  for (final stage in ['history', 'report', 'profile']) {
    test('a pending $stage read rejects an account/platform change', () async {
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      var calls = 0;
      final client = MockClient((request) {
        calls++;
        final isPending =
            stage != 'profile' || request.url.path.startsWith('/weapi/');
        if (isPending) {
          if (!started.isCompleted) started.complete();
          return pending.future;
        }
        return Future.value(_reply(_report));
      });
      addTearDown(client.close);
      final api = NeteaseApi(client)..configure(_session);
      var current = true;
      final repository = NeteaseTogetherRecordsRepository(
        NeteaseMusicRepository(api),
        isCurrent: () => current,
      );
      final read = stage == 'history'
          ? repository.history()
          : repository.report(_room);
      final rejected = expectLater(read, throwsException);
      await started.future;
      current = false;
      // A platform switch can leave a retained NetEase API unchanged. The
      // provider/current callback must still reject the old page's response.
      pending.complete(_reply(stage == 'history' ? _history : _report));
      await rejected;
      expect(calls, stage == 'profile' ? 3 : 1);
    });
  }

  for (final response in [
    http.Response('{"code":500}', 200),
    http.Response('{}', 200),
    _reply({'unrelated': true}),
  ]) {
    test(
      'bad history receipts fail without inventing an empty successful page: ${response.body}',
      () async {
        var count = 0;
        final client = MockClient((_) async {
          count++;
          return response;
        });
        addTearDown(client.close);
        final api = NeteaseApi(client)..configure(_session);
        await expectLater(
          NeteaseTogetherRecordsRepository(
            NeteaseMusicRepository(api),
          ).history(),
          throwsException,
        );
        expect(count, 1);
      },
    );
  }
}
