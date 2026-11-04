import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mesting_music/core/haptics/app_haptics.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/together/netease_together_controller.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_background_binding.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_sync_diagnostics.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_sync_diagnostics_page.dart';
import 'package:mesting_music/shared/models/track.dart';

import 'netease_v114_workflows_test.dart' show FakeTogetherPlayer;
import 'release_142_together_sync_test.dart' show SyntheticTogetherRoom;

const _channel = MethodChannel('com.mesting.music/together_background');
const _codec = StandardMethodCodec();

List<Map<String, Object>> _events(TogetherSyncDiagnostics diagnostics) =>
    (diagnostics.snapshot()['events'] as List).cast<Map<String, Object>>();

Track _song(String id) => Track(
  id: 'netease_$id',
  platformSongId: id,
  source: TrackSource.netease,
  title: 'PRIVATE_SONG_TITLE',
  artist: 'PRIVATE_ARTIST',
  album: '',
  duration: const Duration(minutes: 3),
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
);

void _background(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void _foreground(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

Future<Object?> _pulse(Object arguments) {
  final result = Completer<Object?>();
  ui.channelBuffers.push(
    _channel.name,
    _codec.encodeMethodCall(MethodCall('poll', arguments)),
    (bytes) =>
        result.complete(bytes == null ? null : _codec.decodeEnvelope(bytes)),
  );
  return result.future;
}

/// The actual encrypted transport and controller run, while this gate controls
/// one local status read. It never connects to a service or a real account.
class _GatedClient extends http.BaseClient {
  _GatedClient(this.inner);
  final http.Client inner;
  final gate = Completer<void>(), started = Completer<void>();
  bool blocked = false, failWithTimeout = false;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    if (request.url.path.endsWith('/status/get')) {
      if (failWithTimeout) {
        throw TimeoutException('PRIVATE_EXCEPTION_URL_AND_BODY');
      }
      if (blocked) {
        if (!started.isCompleted) started.complete();
        await gate.future;
      }
    }
    return inner.send(request);
  }
}

class _BlockedPlayer extends FakeTogetherPlayer
    implements NeteaseTogetherCancelablePlayer {
  final gate = Completer<void>(), started = Completer<void>();
  int generation = 0, attempts = 0;

  @override
  void cancelPendingApplication() => generation++;

  @override
  Future<void> apply(
    List<Track> queue,
    String songId,
    Duration position,
    bool playing,
  ) async {
    final own = ++generation;
    if (++attempts == 1) {
      started.complete();
      await gate.future;
    }
    if (own == generation) {
      await super.apply(queue, songId, position, playing);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('journal is bounded and snapshots cannot mutate retained evidence', () {
    final journal = TogetherSyncDiagnostics(
      capacity: 3,
      utcNow: () => DateTime.utc(2026, 11, 3),
    );
    for (var i = 0; i < 5; i++) {
      journal.record(TogetherSyncPhase.pollEntered, request: i);
    }
    final snapshot = journal.snapshot();
    expect(snapshot['dropped'], 2);
    expect(_events(journal).map((e) => e['index']), [3, 4, 5]);
    expect((snapshot['counts'] as Map)['pollEntered'], 5);
    (snapshot['events'] as List).first['phase'] = 'PRIVATE_MUTATION';
    (snapshot['counts'] as Map)['pollEntered'] = -1;
    expect(jsonEncode(journal.snapshot()), isNot(contains('PRIVATE_MUTATION')));
    expect((journal.snapshot()['counts'] as Map)['pollEntered'], 5);
  });

  test('native export rejects unapproved keys and arbitrary event strings', () {
    final snapshot = TogetherSyncDiagnostics.sanitizeNative({
      'capacity': 256,
      'dropped': 2,
      'enabled': true,
      'pending': false,
      'cookie': 'PRIVATE_COOKIE',
      'counts': {'nativePulses': 9, 'userId': 'PRIVATE_USER'},
      'events': [
        {
          'phase': 'pulseSent',
          'request': 2,
          'utcMs': 1000,
          'lease': 'PRIVATE_ROOM_LEASE',
          'url': 'PRIVATE_URL',
        },
        {'phase': 'PRIVATE_BODY', 'request': 3},
      ],
    });
    expect(snapshot['available'], true);
    expect(snapshot['counts'], {'nativePulses': 9});
    expect((snapshot['events'] as List).length, 1);
    expect(jsonEncode(snapshot), isNot(contains('PRIVATE_')));
  });

  test(
    'ordinary build logs nothing and explicit candidate logs the whitelist',
    () {
      final lines = <String>[];
      final ordinary = TogetherSyncDiagnostics(logLine: lines.add);
      ordinary.record(TogetherSyncPhase.httpStarted);
      expect(TogetherSyncDiagnostics.diagnosticLoggingEnabled, false);
      expect(lines, isEmpty);
      expect(ordinary.snapshot()['loggingEnabled'], false);
      final candidate = TogetherSyncDiagnostics(
        logEvents: true,
        logLine: lines.add,
      );
      candidate.record(
        TogetherSyncPhase.httpStarted,
        operation: TogetherSyncOperation.status,
        request: 3,
      );
      final logged = jsonDecode(lines.single) as Map;
      expect(logged['tag'], 'MestingTogetherSync');
      expect(logged['source'], 'dart');
      expect(logged['phase'], 'httpStarted');
      expect(logged['operation'], 'status');
      expect(candidate.snapshot()['loggingEnabled'], true);
      expect(logged.containsKey('url'), false);
      expect(logged.containsKey('body'), false);
      final brokenSink = TogetherSyncDiagnostics(
        logEvents: true,
        logLine: (_) => throw StateError('PRIVATE_LOG_SINK_FAILURE'),
      );
      brokenSink.record(TogetherSyncPhase.pollEntered);
      expect(_events(brokenSink).single['phase'], 'pollEntered');
      expect(jsonEncode(brokenSink.snapshot()), isNot(contains('PRIVATE_')));
    },
  );

  testWidgets(
    'received ACK is distinct from a blocked HTTP and completed application',
    (tester) async {
      _foreground(tester);
      final room = SyntheticTogetherRoom();
      final original = room.music('8');
      final client = _GatedClient(original.api.client);
      final music = NeteaseMusicRepository(
        NeteaseApi(client)..configure(original.api.session),
      );
      final journal = TogetherSyncDiagnostics();
      final player = FakeTogetherPlayer()
        ..track = _song('17')
        ..tracks = [_song('17'), _song('18')];
      final messages = NeteaseMessagesRepository(music);
      final controller = NeteaseTogetherController(
        music: music,
        player: player,
        messages: messages,
        isCurrent: () => true,
        automaticTimer: false,
        diagnostics: journal,
      );
      final configurations = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
        call,
      ) async {
        if (call.method == 'diagnosticSnapshot') {
          return {
            'counts': {'nativePulses': 1, 'nativeAcknowledged': 1},
            'events': [
              {'phase': 'pulseSent', 'request': 1},
              {'phase': 'acknowledged', 'request': 1},
            ],
          };
        }
        final args = call.arguments as Map;
        configurations.add(args);
        return {'accepted': true, 'revision': args['revision']};
      });
      TogetherBackgroundBinding? binding;
      addTearDown(() async {
        if (!client.gate.isCompleted) client.gate.complete();
        binding?.dispose();
        controller.dispose();
        messages.dispose();
        await player.close();
        for (final client in room.clients) {
          client.close();
        }
        _foreground(tester);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          null,
        );
      });
      await controller.restore();
      binding = TogetherBackgroundBinding(
        changes: controller,
        active: () => controller.active && controller.current,
        poll: controller.poll,
        supported: true,
        diagnostics: journal,
      );
      _background(tester);
      await tester.idle();
      client.blocked = true;
      room.latest = {
        'serverSeq': 1,
        'userId': '7',
        'targetSongId': '18',
        'playStatus': 'PLAY',
        'progress': 2500,
      };
      expect(
        await _pulse({'lease': configurations.last['lease'], 'request': 1}),
        true,
      );
      expect(client.started.isCompleted, true);
      expect(player.track?.platformSongId, '17');
      final pending = _events(
        journal,
      ).lastWhere((e) => e['phase'] == 'httpStarted');
      expect(pending['operation'], 'status');
      expect(
        _events(journal).any(
          (e) =>
              e['phase'] == 'httpCompleted' &&
              e['request'] == pending['request'],
        ),
        false,
      );
      expect(
        _events(journal).any((e) => e['phase'] == 'applicationCompleted'),
        false,
      );
      final requestsBeforeExport = client.requests;
      final report = await TogetherBackgroundBinding.captureDiagnostics(
        synchronization: {
          ...controller.synchronizationDiagnostics,
          'PRIVATE_USER': 123,
        },
        journal: journal,
      );
      expect(client.requests, requestsBeforeExport);
      expect(jsonEncode(report), isNot(contains('PRIVATE_')));
      expect(jsonEncode(report), isNot(contains('synthetic-room')));
      expect((report['native'] as Map)['counts'], {
        'nativePulses': 1,
        'nativeAcknowledged': 1,
      });
      client.gate.complete();
      await tester.idle();
      expect(player.track?.platformSongId, '18');
      expect(
        _events(journal).any((e) => e['phase'] == 'applicationCompleted'),
        true,
      );
      expect(
        _events(
          journal,
        ).any((e) => e['phase'] == 'lifecycle' && e['lifecycle'] == 'paused'),
        true,
      );
    },
  );

  testWidgets('timeout exports a phase without the transport error text', (
    tester,
  ) async {
    final room = SyntheticTogetherRoom();
    final original = room.music('8');
    final client = _GatedClient(original.api.client);
    final music = NeteaseMusicRepository(
      NeteaseApi(client)..configure(original.api.session),
    );
    final journal = TogetherSyncDiagnostics();
    final player = FakeTogetherPlayer()
      ..track = _song('17')
      ..tracks = [_song('17'), _song('18')];
    final messages = NeteaseMessagesRepository(music);
    final controller = NeteaseTogetherController(
      music: music,
      player: player,
      messages: messages,
      isCurrent: () => true,
      automaticTimer: false,
      diagnostics: journal,
    );
    addTearDown(() async {
      controller.dispose();
      messages.dispose();
      await player.close();
      for (final client in room.clients) {
        client.close();
      }
    });
    await controller.restore();
    client.failWithTimeout = true;
    await controller.tick();
    expect(
      _events(
        journal,
      ).any((e) => e['phase'] == 'httpTimedOut' && e['operation'] == 'status'),
      true,
    );
    expect(_events(journal).last['phase'], 'tickFailed');
    expect(jsonEncode(journal.snapshot()), isNot(contains('PRIVATE_')));
  });

  testWidgets('new command cancellation and old sequence are distinguishable', (
    tester,
  ) async {
    final room = SyntheticTogetherRoom();
    final music = room.music('8');
    final journal = TogetherSyncDiagnostics();
    final player = _BlockedPlayer()
      ..track = _song('17')
      ..tracks = [_song('17'), _song('18')];
    final messages = NeteaseMessagesRepository(music);
    final controller = NeteaseTogetherController(
      music: music,
      player: player,
      messages: messages,
      isCurrent: () => true,
      automaticTimer: false,
      diagnostics: journal,
    );
    addTearDown(() async {
      if (!player.gate.isCompleted) player.gate.complete();
      controller.dispose();
      messages.dispose();
      await player.close();
      for (final client in room.clients) {
        client.close();
      }
    });
    await controller.restore();
    room.latest = {
      'serverSeq': 1,
      'userId': '7',
      'targetSongId': '18',
      'playStatus': 'PLAY',
    };
    await controller.tick(waitForPlayback: false);
    expect(player.started.isCompleted, true);
    expect(
      _events(journal).any((e) => e['phase'] == 'applicationStarted'),
      true,
    );
    expect(
      _events(journal).any((e) => e['phase'] == 'applicationCompleted'),
      false,
    );
    final first = room.latest;
    room.latest = {
      'serverSeq': 2,
      'userId': '7',
      'targetSongId': '17',
      'playStatus': 'PAUSE',
    };
    await controller.tick();
    expect(
      _events(journal).any(
        (e) =>
            e['phase'] == 'applicationCancelled' &&
            e['reason'] == 'newerCommand',
      ),
      true,
    );
    expect(player.track?.platformSongId, '17');
    room.replay = first;
    await controller.tick();
    expect(
      _events(journal).any(
        (e) => e['phase'] == 'commandSkipped' && e['reason'] == 'olderSequence',
      ),
      true,
    );
    expect(jsonEncode(journal.snapshot()), isNot(contains('synthetic-room')));
    expect(jsonEncode(journal.snapshot()), isNot(contains('PRIVATE_')));
  });

  for (final brightness in Brightness.values) {
    testWidgets('local diagnostic preview/copy works in $brightness at 320dp', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final room = SyntheticTogetherRoom();
      final music = room.music('8');
      final journal = TogetherSyncDiagnostics();
      journal.record(TogetherSyncPhase.pollEntered);
      final player = FakeTogetherPlayer();
      final messages = NeteaseMessagesRepository(music);
      final controller = NeteaseTogetherController(
        music: music,
        player: player,
        messages: messages,
        isCurrent: () => true,
        automaticTimer: false,
        diagnostics: journal,
      );
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        (_) async => {'counts': <String, int>{}, 'events': <Object>[]},
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(() async {
        controller.dispose();
        messages.dispose();
        await player.close();
        for (final client in room.clients) {
          client.close();
        }
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          null,
        );
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appHapticsProvider.overrideWithValue(
              AppHaptics(
                preferences: () => const HapticPreferences(enabled: false),
                bridge: HapticBridge(),
              ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: TogetherSyncDiagnosticsPage(controller: controller),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('一起听同步诊断'), findsOneWidget);
      expect(find.text('已读取本机诊断'), findsOneWidget);
      await tester.ensureVisible(find.text('复制脱敏报告'));
      await tester.tap(find.text('复制脱敏报告'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(copied, contains('mesting-together-sync-v1'));
      expect(copied, contains('pollEntered'));
      expect(copied, isNot(contains('PRIVATE_')));
      expect(find.text('脱敏报告已复制'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
