import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/music_equalizer.dart';
import 'package:mesting_music/core/audio/music_sleep_timer.dart';
import 'package:mesting_music/core/audio/playback_interruption.dart';

class TestEqualizerBridge implements MusicEqualizerBridge {
  final binds = <int>[],
      applied = <({int session, bool enabled, List<double> levels})>[];
  bool failApply = false;
  int releases = 0;
  Completer<EqualizerParameters>? pending;
  static const parameters = EqualizerParameters(
    frequencies: [60000, 230000, 910000, 3600000, 14000000],
    levels: [0, 0, 0, 0, 0],
    minimum: -10,
    maximum: 10,
  );
  @override
  Future<EqualizerParameters> bind(int sessionId) async {
    binds.add(sessionId);
    return pending?.future ?? parameters;
  }

  @override
  Future<EqualizerParameters> apply(
    int sessionId, {
    required bool enabled,
    required List<double> levels,
  }) async {
    if (failApply) throw StateError('device fixture');
    applied.add((
      session: sessionId,
      enabled: enabled,
      levels: List.of(levels),
    ));
    return EqualizerParameters(
      frequencies: parameters.frequencies,
      levels: levels,
      minimum: -10,
      maximum: 10,
    );
  }

  @override
  Future<void> release() async {
    releases++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> flush() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<
    (
      MusicEqualizerController,
      TestEqualizerBridge,
      StreamController<int?>,
      SharedPreferences,
    )
  >
  prepare({Map<String, Object> initial = const {}, int? session = 7}) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    final bridge = TestEqualizerBridge(),
        sessions = StreamController<int?>.broadcast();
    final controller = MusicEqualizerController(
      bridge: bridge,
      preferences: prefs,
      sessions: sessions.stream,
      currentSession: session,
    );
    addTearDown(() async {
      controller.dispose();
      await sessions.close();
    });
    return (controller, bridge, sessions, prefs);
  }

  test(
    'EQ enables the actual session, maps a curve and persists its choice',
    () async {
      final (controller, bridge, _, prefs) = await prepare();
      await controller.selectPreset(
        '重低音',
        effectId: 'fixture-bass',
        effectName: '测试低音',
      );
      expect(bridge.binds, [7]);
      expect(bridge.applied.last.enabled, true);
      expect(bridge.applied.last.levels, [6, 6, 0, 0, 0]);
      expect(controller.state.bound, true);
      final stored = jsonDecode(prefs.getString(musicEqualizerPreferenceKey)!);
      expect(stored['preset'], '重低音');
      expect(stored['effectId'], 'fixture-bass');
      await controller.setEnabled(false);
      expect(bridge.applied.last.enabled, false);
      expect(controller.state.preset, '重低音');
    },
  );
  test('EQ restores the saved curve to a replacement audio session', () async {
    final (controller, bridge, sessions, _) = await prepare(
      initial: {
        musicEqualizerPreferenceKey: jsonEncode({
          'enabled': true,
          'preset': '人声',
          'frequencies': [60000, 230000, 910000, 3600000, 14000000],
          'levels': [-2, -2, 4, 3, -1],
        }),
      },
    );
    await flush();
    expect(bridge.applied.last.session, 7);
    expect(bridge.applied.last.levels, [-2, -2, 4, 3, -1]);
    sessions.add(19);
    await flush();
    expect(bridge.applied.last.session, 19);
    expect(controller.state.preset, '人声');
  });
  test('failed EQ change retains the previously saved selection', () async {
    final (controller, bridge, _, prefs) = await prepare();
    await controller.selectPreset('人声');
    final saved = prefs.getString(musicEqualizerPreferenceKey);
    bridge.failApply = true;
    await controller.selectPreset('电子');
    expect(controller.state.preset, '人声');
    expect(controller.state.message, isNotNull);
    expect(prefs.getString(musicEqualizerPreferenceKey), saved);
  });
  test('stale native bind cannot apply to a replaced session', () async {
    final (controller, bridge, sessions, _) = await prepare();
    bridge.pending = Completer<EqualizerParameters>();
    final pending = controller.bind();
    await flush();
    sessions.add(9);
    await flush();
    bridge.pending!.complete(TestEqualizerBridge.parameters);
    await pending;
    await flush();
    expect(bridge.applied.where((v) => v.session == 7), isEmpty);
    bridge.pending = null;
    await controller.bind();
    expect(bridge.applied.last.session, 9);
  });
  test(
    'no-session EQ selection is saved visibly as pending, then applies',
    () async {
      final (controller, bridge, sessions, prefs) = await prepare(
        session: null,
      );
      await controller.selectPreset('爵士');
      expect(bridge.applied, isEmpty);
      expect(controller.state.bound, false);
      expect(controller.state.message, contains('播放'));
      expect(
        jsonDecode(prefs.getString(musicEqualizerPreferenceKey)!)['enabled'],
        true,
      );
      sessions.add(4);
      await flush();
      expect(bridge.applied.last.session, 4);
      expect(controller.state.bound, true);
    },
  );
  test(
    'dragged EQ values clamp to hardware range and clear the catalogue badge',
    () async {
      final (controller, bridge, _, prefs) = await prepare();
      await controller.selectPreset(
        '流行',
        effectId: 'fixture',
        effectName: '示例音效',
      );
      controller.previewBand(0, 50);
      expect(controller.state.levels.first, 10);
      expect(controller.state.effectId, isNull);
      await controller.commitBands();
      expect(bridge.applied.last.levels.first, 10);
      expect(
        jsonDecode(prefs.getString(musicEqualizerPreferenceKey)!)['preset'],
        '自定义',
      );
    },
  );
  test(
    'corrupt EQ preferences fall back without affecting a music identity',
    () async {
      final (controller, _, _, _) = await prepare(
        initial: {musicEqualizerPreferenceKey: 'invalid-json'},
      );
      expect(controller.state.enabled, false);
      expect(controller.state.preset, '正常');
    },
  );
  test(
    'sleep countdown catches a delayed background tick and expires once',
    () async {
      var now = DateTime(2026, 10, 27, 22), pauses = 0;
      final timer = MusicSleepTimer(
        now: () => now,
        onExpire: () async {
          pauses++;
        },
      );
      addTearDown(timer.dispose);
      timer.start(const Duration(minutes: 15));
      now = now.add(const Duration(minutes: 20));
      expect(timer.checkDeadline(), true);
      await flush();
      expect(pauses, 1);
      expect(timer.active, false);
      expect(timer.checkDeadline(), false);
    },
  );
  test(
    'sleep track completion cancels itself before pausing and cancel prevents it',
    () async {
      var pauses = 0;
      final timer = MusicSleepTimer(
        onExpire: () async {
          pauses++;
        },
      );
      addTearDown(timer.dispose);
      timer.afterCurrentTrack();
      expect(timer.consumeTrackCompletion(), true);
      expect(timer.consumeTrackCompletion(), false);
      await flush();
      expect(pauses, 1);
      timer.afterCurrentTrack();
      timer.cancel();
      expect(timer.consumeTrackCompletion(), false);
      expect(pauses, 1);
    },
  );
  test('sleep timer rejects zero/negative or unbounded durations', () {
    final timer = MusicSleepTimer(onExpire: () async {});
    addTearDown(timer.dispose);
    expect(() => timer.start(Duration.zero), throwsArgumentError);
    expect(() => timer.start(const Duration(hours: 25)), throwsArgumentError);
  });
  test(
    'MV interruption resumes the same music owner without seeking or rebuilding',
    () async {
      var id = 'original', revision = 0, playing = true, plays = 0;
      final lease = MusicPlaybackInterruption(
        mediaId: () => id,
        revision: () => revision,
        playing: () => playing,
        pause: () async {
          revision++;
          playing = false;
        },
        play: () async {
          plays++;
          playing = true;
          revision++;
        },
      );
      await lease.acquire();
      expect(playing, false);
      expect(lease.isCurrent, true);
      await lease.release();
      await lease.release();
      expect(plays, 1);
      expect(id, 'original');
    },
  );
  test(
    'a later timer/user pause or song change prevents MV music resume',
    () async {
      var id = 'original', revision = 0, plays = 0;
      final lease = MusicPlaybackInterruption(
        mediaId: () => id,
        revision: () => revision,
        playing: () => true,
        pause: () async {
          revision++;
        },
        play: () async {
          plays++;
        },
      );
      await lease.acquire();
      revision++;
      id = 'another';
      await lease.release();
      expect(plays, 0);
    },
  );
  test(
    'an action during a slow modal pause supersedes its original ticket',
    () async {
      var revision = 0, plays = 0;
      final gate = Completer<void>();
      final lease = MusicPlaybackInterruption(
        mediaId: () => 'same',
        revision: () => revision,
        playing: () => true,
        pause: () {
          revision++;
          return gate.future;
        },
        play: () async {
          plays++;
        },
      );
      final pending = lease.acquire();
      revision++;
      gate.complete();
      await pending;
      await lease.release();
      expect(plays, 0);
    },
  );
  test('music already paused before MV stays paused on return', () async {
    var plays = 0;
    final lease = MusicPlaybackInterruption(
      mediaId: () => 'same',
      revision: () => 0,
      playing: () => false,
      pause: () async {},
      play: () async {
        plays++;
      },
    );
    await lease.acquire();
    await lease.release();
    expect(plays, 0);
  });
}
