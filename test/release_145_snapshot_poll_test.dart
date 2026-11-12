import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/together/netease_together_controller.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_shared_playlist.dart';
import 'netease_v114_workflows_test.dart' show FakeTogetherPlayer;
import 'release_142_together_sync_test.dart' show SyntheticTogetherRoom;

/// Models the observed transport boundary: membership/heartbeat return no
/// command; only the shared playback snapshot returns the peer's latest state.
/// Two real controllers still exchange actual encrypted command requests via
/// the existing in-memory room. No account/network is accessed.
class _SnapshotOnlyClient extends http.BaseClient {
  _SnapshotOnlyClient(this.inner, this.room);
  final http.Client inner;
  final SyntheticTogetherRoom room;
  int playlistReads = 0, songReads = 0;
  final order = <String>[];
  Completer<void>? holdNext, captured;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    order.add(path);
    if (path.contains('song/detail')) songReads++;
    final response = await http.Response.fromStream(await inner.send(request));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (path.endsWith('/room/check') || path.endsWith('/heartbeat')) {
      payload['data'] = <String, dynamic>{};
    } else if (path.endsWith('/sync/playlist/get')) {
      playlistReads++;
      payload['data'] = {
        ...payload['data'] as Map<String, dynamic>,
        if ((room.replay ?? room.latest) != null)
          'commandInfo': Map<String, dynamic>.from(
            (room.replay ?? room.latest)!,
          ),
      };
      final held = holdNext;
      holdNext = null;
      if (held != null) {
        captured!.complete();
        await held.future;
      }
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(payload))),
      response.statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyntheticTogetherRoom room;
  late List<FakeTogetherPlayer> players;
  late List<NeteaseTogetherController> controllers;
  late List<_SnapshotOnlyClient> transports;
  setUp(() async {
    room = SyntheticTogetherRoom();
    players = [];
    controllers = [];
    transports = [];
    for (final user in ['7', '8']) {
      final original = room.music(user);
      final transport = _SnapshotOnlyClient(original.api.client, room);
      transports.add(transport);
      final music = NeteaseMusicRepository(
        NeteaseApi(transport)..configure(
          NeteaseSession(
            userId: user,
            deviceId: 'fixture-$user',
            cookies: const {'MUSIC_U': 'synthetic-only'},
          ),
        ),
      );
      final player = FakeTogetherPlayer();
      players.add(player);
      final controller = NeteaseTogetherController(
        music: music,
        player: player,
        messages: NeteaseMessagesRepository(music),
        isCurrent: () => true,
        automaticTimer: false,
      );
      controllers.add(controller);
      await controller.restore();
      player.tracks = controller.sharedTracks;
      player.track = player.tracks.first;
    }
  });
  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
    }
    for (final p in players) {
      await p.close();
    }
    for (final c in room.clients) {
      c.close();
    }
  });
  Future<void> command(
    int from, {
    String? song,
    bool? play,
    int seconds = 20,
  }) async {
    final p = players[from];
    if (song != null) {
      p.track = p.tracks.firstWhere((t) => t.platformSongId == song);
    }
    if (play != null) p.playing = play;
    p.position = Duration(seconds: seconds);
    p.commandController.add(
      song != null
          ? 'next'
          : play == false
          ? 'pause'
          : 'play',
    );
    await controllers[from].settle();
  }

  for (final from in [0, 1]) {
    test(
      'snapshot-only peer song/pause/play syncs by tick in both directions from=$from',
      () async {
        final to = 1 - from, target = players[to], transport = transports[to];
        final details = transport.songReads;
        await command(from, song: '18', seconds: 37);
        transport.order.clear();
        await controllers[to].tick();
        expect(target.track?.platformSongId, '18');
        expect(target.position.inSeconds, 37);
        expect(
          transport.order.indexWhere((p) => p.endsWith('/sync/playlist/get')),
          lessThan(transport.order.indexWhere((p) => p.endsWith('/heartbeat'))),
        );
        await command(from, play: false, seconds: 39);
        await controllers[to].tick();
        expect(target.playing, false);
        await command(from, play: true, seconds: 42);
        await controllers[to].tick();
        expect(target.playing, true);
        expect(target.position.inSeconds, 42);
        expect(
          transport.songReads,
          details,
          reason: 'known metadata is not fetched on every snapshot',
        );
        final applications = target.applications, writes = room.writes.length;
        await controllers[to].tick();
        await controllers[to].settle();
        expect(target.applications, applications);
        expect(room.writes.length, writes);
      },
    );
  }

  test(
    'new shared queue resolves metadata once, then reuses it on following ticks',
    () async {
      final peer = players[1], transport = transports[1];
      final before = transport.songReads;
      room.playlist = ['19'];
      room.latest = {
        'targetSongId': '19',
        'serverSeq': 101,
        'playStatus': 'PLAY',
        'progress': 27000,
        'userId': '7',
      };
      await controllers[1].tick();
      expect(peer.track?.platformSongId, '19');
      expect(peer.position.inSeconds, 27);
      expect(transport.songReads, before + 1);
      await controllers[1].tick();
      expect(transport.songReads, before + 1);
    },
  );

  test(
    'late pre-resume snapshot cannot replace a newer queue or playback state',
    () async {
      final target = controllers[1], transport = transports[1];
      room.latest = {
        'targetSongId': '18',
        'serverSeq': 101,
        'playStatus': 'PLAY',
        'progress': 27000,
        'userId': '7',
      };
      final held = Completer<void>();
      transport.holdNext = held;
      transport.captured = Completer<void>();
      final firstTick = target.tick();
      await transport.captured!.future;
      room.playlist = ['19'];
      room.latest = {
        'targetSongId': '19',
        'serverSeq': 102,
        'playStatus': 'PAUSE',
        'progress': 31000,
        'userId': '7',
      };
      await target.restore();
      held.complete();
      await firstTick;
      expect(players[1].track?.platformSongId, '19');
      expect(players[1].playing, false);
      expect(target.sharedTracks.map((t) => t.platformSongId), ['19']);
    },
  );

  test(
    'older snapshot command remains rejected after a new sequence',
    () async {
      await command(0, song: '18');
      await controllers[1].tick();
      room.replay = {
        'targetSongId': '17',
        'serverSeq': 0,
        'playStatus': 'PAUSE',
        'progress': 0,
        'userId': '7',
      };
      await controllers[1].tick();
      expect(players[1].track?.platformSongId, '18');
      expect(players[1].playing, true);
    },
  );

  test(
    'wrapped/reordered playlists use complete cache; missing tracks request details',
    () {
      final tracks = controllers[1].sharedTracks;
      final snapshot = TogetherSharedPlaylist({
        'playlist': {
          'displayList': {
            'result': ['18', '17'],
          },
        },
      });
      expect(snapshot.reuse(tracks)?.map((t) => t.platformSongId), [
        '18',
        '17',
      ]);
      expect(
        TogetherSharedPlaylist({
          'playlist': {
            'displayList': ['19'],
          },
        }).reuse(tracks),
        isNull,
      );
    },
  );
}
