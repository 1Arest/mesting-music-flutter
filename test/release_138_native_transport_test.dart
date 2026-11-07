import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_models.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_store.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_listening_reporter.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_native_journal.dart';
import 'package:mesting_music/features/music_platform/netease/netease_native_log.dart';
import 'netease_v112_listening_test.dart' show session, song;
import 'release_107_listening_sync_test.dart' show FakeClock, FakeFeed;

class NativeClient extends http.BaseClient {
  NativeClient(this.reply);
  final Map<String, Object?> Function(String filename) reply;
  final requests = <http.BaseRequest>[];
  final sequences = <int>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final body = await request.finalize().toBytes();
    expect(request.url.host, 'clientlog3.music.163.com');
    expect(request.url.path, '/api/clientlog/encrypt/upload');
    expect(request.url.queryParameters, {'multiupload': 'false'});
    final start = utf8.decode(body.take(240).toList(), allowMalformed: true);
    final filename = RegExp('filename="([^"]+)"').firstMatch(start)![1]!;
    final marker = body.indexOf(0x4e);
    expect(ascii.decode(body.sublist(marker, marker + 4)), 'NCBL');
    final header = Uint8List.sublistView(body, marker);
    sequences.add(ByteData.sublistView(header).getUint32(58, Endian.little));
    final uuid = Uint8List.sublistView(header, 10, 26);
    final n = ByteData.sublistView(header).getUint16(72, Endian.little);
    final decryptedInfo = NeteaseNativeLog.chacha(
      Uint8List.sublistView(header, 74, 74 + n),
      Uint8List.sublistView(header, 26, 58),
      Uint8List.sublistView(uuid, 0, 12),
      ByteData.sublistView(uuid).getUint32(12, Endian.little) >> 2,
    );
    final info = jsonDecode(utf8.decode(decryptedInfo));
    expect(info['MUSIC_U'], session.cookies['MUSIC_U']);
    expect(info['os'], 'android');
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(reply(filename)))),
      200,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'logout during a native request keeps the old write uncertain',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = ListeningSyncStore(db);
      late NeteaseApi api;
      final client = NativeClient((filename) {
        api.configure(null);
        return {
          'code': 200,
          'data': {
            'successfiles': [filename],
          },
        };
      });
      api = NeteaseApi(client)..configure(session);
      final now = DateTime(2026, 11, 2);
      await store.put(
        owner: 'netease:7',
        id: 'old-owner',
        kind: 'netease-scrobble',
        payload: {
          'id': '17',
          'time': 30,
          'realtime': 30,
          'protocolVersion': 3,
          'eventlogtime': now.millisecondsSinceEpoch ~/ 1000,
        },
        now: now,
      );
      final reporter = NeteaseListeningReporter(
        feed: FakeFeed(),
        music: NeteaseMusicRepository(api, nativeLogEnabled: true),
        store: store,
        current: () => true,
        automaticTimers: false,
        observeLifecycle: false,
      );
      await reporter.settle();
      expect(
        (await store.entry('netease:7', 'old-owner'))!.state,
        ListeningSyncState.unknown,
      );
      await reporter.recoverPending();
      expect(client.requests, hasLength(1));
      reporter.dispose();
      await reporter.settle();
    },
  );
  test('a replaced credential is rejected before any native request', () async {
    final client = NativeClient(
      (name) => {
        'code': 200,
        'data': {
          'successfiles': [name],
        },
      },
    );
    final api = NeteaseApi(client)..configure(session);
    final repository = NeteaseMusicRepository(api, nativeLogEnabled: true);
    api.configure(null);
    await expectLater(
      repository.reportPlayback(id: '17', started: true, nativeSequence: 0),
      throwsException,
    );
    expect(client.requests, isEmpty);
  });
  for (final outcome in ['accepted', 'unknown', 'rejected']) {
    test(
      'native $outcome requires per-file receipt and never replays',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final store = ListeningSyncStore(db);
        final client = NativeClient(
          (name) => switch (outcome) {
            'accepted' => {
              'code': 200,
              'data': jsonEncode({
                'successfiles': [name],
              }),
            },
            'unknown' => {
              'code': 200,
              'data': {
                'successfiles': ['another-file'],
              },
            },
            _ => {'code': 301},
          },
        );
        final api = NeteaseApi(client)..configure(session);
        final before = Map.from(api.cookies);
        final now = DateTime(2026, 11, 2);
        await store.put(
          owner: 'netease:7',
          id: 'native',
          kind: 'netease-scrobble',
          payload: {
            'id': '17',
            'time': 30,
            'realtime': 30,
            'heardMs': 30000,
            'protocolVersion': 3,
            'startlogtime': now.millisecondsSinceEpoch ~/ 1000,
            'eventlogtime':
                now.add(const Duration(seconds: 30)).millisecondsSinceEpoch ~/
                1000,
          },
          now: now,
        );
        final reporter = NeteaseListeningReporter(
          feed: FakeFeed(),
          music: NeteaseMusicRepository(api, nativeLogEnabled: true),
          store: store,
          current: () => true,
          automaticTimers: false,
          observeLifecycle: false,
        );
        await reporter.settle();
        expect((await store.entry('netease:7', 'native'))!.state.name, outcome);
        await reporter.recoverPending();
        reporter.dispose();
        await reporter.settle();
        expect(client.requests, hasLength(1));
        expect(api.cookies, before);
      },
    );
  }
  test(
    'claim serializes sequence reservation and refuses already dispatched rows',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = ListeningSyncStore(db);
      final now = DateTime(2026, 11, 2);
      for (final id in ['a', 'b']) {
        await store.put(
          owner: 'netease:7',
          id: id,
          kind: 'netease-startplay',
          payload: const {'protocolVersion': 3},
          now: now,
        );
      }
      final a = (await store.entry('netease:7', 'a'))!;
      final claims = await Future.wait([
        claimNeteaseNativeLog(store, a, now),
        claimNeteaseNativeLog(store, a, now),
      ]);
      expect(claims.whereType<ListeningSyncEntry>(), hasLength(1));
      expect(
        claims.whereType<ListeningSyncEntry>().single.number('nativeSequence'),
        0,
      );
      final b = await claimNeteaseNativeLog(
        store,
        (await store.entry('netease:7', 'b'))!,
        now,
      );
      expect(b!.number('nativeSequence'), 1);
    },
  );
  test(
    'candidate flags only new plays and preserves measured timestamps',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = ListeningSyncStore(db);
      final clock = FakeClock();
      final feed = FakeFeed();
      addTearDown(feed.close);
      feed.setTrack(song);
      feed.setState(true, true);
      final client = NativeClient(
        (name) => {
          'code': 200,
          'data': {
            'successfiles': [name],
          },
        },
      );
      final api = NeteaseApi(client)..configure(session);
      final reporter = NeteaseListeningReporter(
        feed: feed,
        music: NeteaseMusicRepository(api, nativeLogEnabled: true),
        store: store,
        current: () => true,
        clock: clock,
        automaticTimers: false,
        observeLifecycle: false,
      );
      await reporter.settle();
      clock.elapse(61000);
      feed.setTrack(null);
      await reporter.settle();
      final entries = await store.entries(
        'netease:7',
        kinds: {'netease-scrobble'},
      );
      expect(entries.single.number('realtime'), 61);
      expect(
        entries.single.number('eventlogtime') -
            entries.single.number('startlogtime'),
        61,
      );
      expect(entries.single.text('endReason'), 'interrupt');
      expect(client.sequences, [0, 1]);
      reporter.dispose();
      await reporter.settle();
    },
  );
}
