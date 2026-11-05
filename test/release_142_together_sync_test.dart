import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/together/netease_together_controller.dart';
import 'package:mesting_music/shared/models/track.dart';

import 'netease_v114_workflows_test.dart' show FakeTogetherPlayer, eapiBody;

const _first = Track(
  id: 'netease_17',
  platformSongId: '17',
  source: TrackSource.netease,
  title: '合成歌曲一',
  artist: '合成测试',
  album: '合成样本',
  duration: Duration(minutes: 4),
  audioAsset: '',
  lyricsAsset: '',
  coverAsset: '',
);
const _second = Track(
  id: 'netease_18',
  platformSongId: '18',
  source: TrackSource.netease,
  title: '合成歌曲二',
  artist: '合成测试',
  album: '合成样本',
  duration: Duration(minutes: 3),
  audioAsset: '',
  lyricsAsset: '',
  coverAsset: '',
);

const _outsideQueue = Track(
  id: 'netease_19',
  platformSongId: '19',
  source: TrackSource.netease,
  title: '另一歌单的合成歌曲',
  artist: '合成测试',
  album: '合成样本',
  duration: Duration(minutes: 3),
  audioAsset: '',
  lyricsAsset: '',
  coverAsset: '',
);

// A shared in-memory room carries the actual decoded EAPI command envelope
// between two independent controllers. Neither client reaches an account.
class SyntheticTogetherRoom {
  Map<String, dynamic>? latest, replay;
  int sequence = 0, failSongReads = 0;
  bool delayHeartbeat = false;
  List<String> playlist = ['17', '18'];
  int playlistWrites = 0;
  final writes = <Map<String, dynamic>>[];
  final clients = <http.Client>[];
  http.Response reply(Map<String, Object?> fields) => http.Response(
    jsonEncode({'code': 200, ...fields}),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  NeteaseMusicRepository music(String user) {
    final client = MockClient((request) async {
      final path = request.url.path;
      Map<String, Object?> data = {};
      if (path.endsWith('/status/get')) {
        data = {
          'inRoom': true,
          'roomInfo': {'roomId': 'synthetic-room', 'roomUsers': []},
        };
      } else if (path.endsWith('/room/check') || path.endsWith('/heartbeat')) {
        if (delayHeartbeat && path.endsWith('/heartbeat')) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        data = {'commandInfo': replay ?? latest};
      } else if (path.endsWith('/sync/list/command/report')) {
        final body = eapiBody(request);
        final value = jsonDecode('${body['playlistParam']}') as Map;
        playlist = (value['displayList'] as List).map((id) => '$id').toList();
        playlistWrites++;
      } else if (path.endsWith('/sync/playlist/get')) {
        data = {
          'playlist': {'displayList': playlist},
        };
      } else if (path.contains('song/detail')) {
        if (failSongReads > 0) {
          failSongReads--;
          throw http.ClientException('Synthetic transient song read');
        }
        return reply({
          'songs': [
            for (final id in playlist.map(int.parse))
              {
                'id': id,
                'name': '合成歌曲$id',
                'dt': 240000,
                'ar': [
                  {'name': '合成测试'},
                ],
                'al': {'name': '合成样本'},
              },
          ],
        });
      } else if (path.endsWith('/play/command/report')) {
        final body = eapiBody(request);
        final command = Map<String, dynamic>.from(
          jsonDecode('${body['commandInfo']}') as Map,
        );
        latest = {...command, 'serverSeq': ++sequence, 'userId': user};
        writes.add(Map.from(latest!));
        data = {'commandInfo': latest};
      }
      return reply({'data': data});
    });
    clients.add(client);
    return NeteaseMusicRepository(
      NeteaseApi(client)..configure(
        NeteaseSession(
          userId: user,
          deviceId: 'synthetic-$user',
          cookies: const {'MUSIC_U': 'fixture'},
        ),
      ),
    );
  }
}

class _LateTrackPlayer extends FakeTogetherPlayer {
  @override
  Future<void> apply(
    List<Track> queue,
    String id,
    Duration position,
    bool playing,
  ) async {
    await super.apply(queue, id, position, playing);
    // Model a media-item publication delivered after the apply Future returns.
    Timer.run(() => trackController.add(track!.id));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyntheticTogetherRoom room;
  late List<FakeTogetherPlayer> players;
  late List<NeteaseTogetherController> controllers;
  Future<void> prepare({bool latePeerTrack = false}) async {
    room = SyntheticTogetherRoom();
    players = [
      FakeTogetherPlayer(),
      latePeerTrack ? _LateTrackPlayer() : FakeTogetherPlayer(),
    ];
    controllers = [];
    for (var index = 0; index < 2; index++) {
      players[index]
        ..track = _first
        ..tracks = [_first, _second];
      final music = room.music('${7 + index}');
      final controller = NeteaseTogetherController(
        music: music,
        player: players[index],
        messages: NeteaseMessagesRepository(music),
        isCurrent: () => true,
        automaticTimer: false,
      );
      controllers.add(controller);
      await controller.restore();
    }
  }

  tearDown(() async {
    for (final controller in controllers) {
      controller.dispose();
    }
    for (final player in players) {
      await player.close();
    }
    for (final client in room.clients) {
      client.close();
    }
  });

  for (final sender in [0, 1]) {
    test(
      'play and pause intent reaches the other participant sender=$sender',
      () async {
        await prepare();
        final peer = 1 - sender;
        // Production announces pause before its fade has paused the native audio.
        players[sender].commandController.add('pause');
        await controllers[sender].settle();
        players[sender].playing = false;
        await controllers[peer].tick();
        expect(players[peer].playing, false);
        expect(room.writes.last['playStatus'], 'PAUSE');
        players[sender].commandController.add('play');
        await controllers[sender].settle();
        players[sender].playing = true;
        await controllers[peer].tick();
        expect(players[peer].playing, true);
        expect(room.writes.last['playStatus'], 'PLAY');
        expect(
          room.writes.length,
          2,
          reason: 'Applying peer state must not echo a new command.',
        );
      },
    );

    test(
      'a selected song reaches the other participant sender=$sender',
      () async {
        await prepare();
        players[sender].track = _second;
        players[sender].trackController.add(_second.id);
        await controllers[sender].settle();
        await controllers[1 - sender].tick();
        expect(players[1 - sender].track?.platformSongId, '18');
        expect(room.writes.last['targetSongId'], '18');
        expect(room.writes.length, 1);
      },
    );
  }

  test('an older response cannot undo a newer server play state', () async {
    await prepare();
    players[0].playing = false;
    players[0].commandController.add('pause');
    await controllers[0].settle();
    final old = Map<String, dynamic>.from(room.latest!);
    await controllers[1].tick();
    players[0].playing = true;
    players[0].commandController.add('play');
    await controllers[0].settle();
    await controllers[1].tick();
    expect(players[1].playing, true);
    room.replay = old;
    await controllers[1].tick();
    expect(players[1].playing, true);
  });

  test(
    'selecting outside the shared queue publishes it before the song command',
    () async {
      await prepare();
      players[0]
        ..tracks = [_outsideQueue]
        ..track = _outsideQueue;
      players[0].trackController.add(_outsideQueue.id);
      await controllers[0].settle();
      await controllers[1].tick();
      expect(players[1].track?.platformSongId, '19');
      expect(room.playlist, ['19']);
      expect(room.playlistWrites, 1);
    },
  );

  test(
    'a delayed remote media publication is not re-broadcast as a local skip',
    () async {
      await prepare(latePeerTrack: true);
      room.delayHeartbeat = true;
      players[0].track = _second;
      players[0].trackController.add(_second.id);
      await controllers[0].settle();
      await controllers[1].tick();
      await Future<void>.delayed(Duration.zero);
      await controllers[1].settle();
      expect(players[1].track?.platformSongId, '18');
      expect(room.writes.length, 1);
    },
  );

  test(
    'failed song loading does not consume a command before it is applied',
    () async {
      await prepare();
      controllers[1].sharedTracks = controllers[1].sharedTracks
          .where((t) => t.platformSongId == '17')
          .toList();
      // Exhaust both bounded read attempts before verifying the command stays
      // unconsumed. The next tick then succeeds with the original command.
      room.failSongReads = 2;
      players[0].track = _second;
      players[0].trackController.add(_second.id);
      await controllers[0].settle();
      await controllers[1].tick();
      expect(players[1].track?.platformSongId, '17');
      await controllers[1].tick();
      expect(players[1].track?.platformSongId, '18');
    },
  );
}
