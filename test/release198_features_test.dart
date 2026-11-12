import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/music_rhythm.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/features/music_platform/default_playback_quality.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/netease/netease_official_ranking_page.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_content.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_social_card.dart';
import 'package:mesting_music/features/themes/profile_effect_style.dart';
import 'package:mesting_music/features/themes/profile_effect_picker.dart';
import 'support/ui_fix_capture.dart';

void main() {
  setUpAll(initializeUiFixCapture);
  test(
    'meter display is silent for absent, invalid or zero PCM and bounds peaks',
    () {
      for (final value in [double.nan, double.infinity, 0, -1]) {
        expect(
          MusicRhythmFrame.parse({'available': true, 'rms': value}).level,
          0,
        );
      }
      expect(MusicRhythmFrame.parse({'rms': 1}).available, false);
      expect(MusicRhythmFrame.parse({'available': true, 'rms': 10}).level, 1);
      expect(
        MusicRhythmFrame.parse({'available': true, 'rms': .1}).level,
        greaterThan(
          MusicRhythmFrame.parse({'available': true, 'rms': .01}).level,
        ),
      );
    },
  );
  testWidgets(
    'one sampler serializes shared owners and drops a late frame after release',
    (tester) async {
      final pending = Completer<Map<String, Object?>>();
      final calls = <bool>[];
      final meter = MusicRhythmSampler((enabled) async {
        calls.add(enabled);
        return enabled ? pending.future : {};
      });
      final a = Object(), b = Object();
      meter.lease(a, true);
      meter.lease(b, true);
      await tester.pump(const Duration(milliseconds: 150));
      expect(calls, [true]);
      meter.lease(a, false);
      meter.lease(b, false);
      pending.complete({'available': true, 'rms': .8});
      await tester.pump();
      expect(meter.value.level, 0);
      expect(calls, [true, false]);
      meter.dispose();
      await tester.pump();
    },
  );
  test(
    'quality defaults are source-specific, persist and reject invalid tiers',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      expect(
        preferredPlaybackQuality(
          container.read(defaultPlaybackQualityProvider),
          TrackSource.netease,
        ),
        PlatformAudioQuality.vivid,
      );
      expect(
        preferredPlaybackQuality(
          container.read(defaultPlaybackQualityProvider),
          TrackSource.kugou,
        ),
        PlatformAudioQuality.hiRes,
      );
      await container
          .read(defaultPlaybackQualityProvider.notifier)
          .select(TrackSource.kugou, '128');
      await container
          .read(defaultPlaybackQualityProvider.notifier)
          .select(TrackSource.kugou, 'netease_vivid');
      expect(
        container.read(defaultPlaybackQualityProvider)[TrackSource.kugou],
        '128',
      );
      expect(
        container.read(defaultPlaybackQualityProvider)[TrackSource.netease],
        'auto',
      );
      expect(
        prefs.getString(DefaultPlaybackQuality.key(TrackSource.kugou)),
        '128',
      );
      await container
          .read(profileEffectProvider.notifier)
          .select(ProfileEffectStyle.rhythm);
      expect(prefs.getString('profile_effect_193'), 'rhythm');
    },
  );
  test(
    'official records select the requested period and never turn score into plays',
    () {
      final result = NeteaseOfficialPlayRecord.parse({
        'weekData': [
          {
            'song': {'id': 1, 'name': '一首歌'},
            'score': 100,
            'playCount': 7,
          },
          {
            'song': {'id': 2, 'name': '另一首歌'},
            'score': 80,
          },
        ],
        'allData': [
          {
            'song': {'id': 1, 'name': '一首歌'},
            'playCount': 22,
          },
        ],
      }, weekly: true);
      expect(result.map((e) => e.count), [7, null]);
      expect(
        NeteaseOfficialPlayRecord.parse({
          'allData': [
            {
              'song': {'id': 1, 'name': '一首歌'},
              'playCount': 22,
            },
          ],
        }, weekly: false).single.count,
        22,
      );
    },
  );
  test('social JSON keeps event identity, body and attached song separate', () {
    final result = NeteaseContent.parse({
      'events': [
        {
          'id': 20,
          'time': 1700000000000,
          'user': {'nickname': '朋友'},
          'json': '{"msg":"分享一首歌","song":{"id":30,"name":"歌曲"}}',
        },
      ],
      'more': true,
      'lasttime': 1699999999000,
    }, '/user/event');
    expect(result.rows.single.kind, 'event');
    expect(result.rows.single.id, '20');
    expect(result.rows.single.title, '分享一首歌');
    expect(result.rows.single.raw['song']['id'], 30);
    expect(result.facts, isEmpty);
    expect(result.more, true);
    expect(result.cursor, 1699999999000);
  });
  test(
    'historical comments deduplicate by ID and use response/last row time as cursor',
    () {
      final result = NeteaseContent.parse({
        'data': {
          'comments': [
            {'commentId': 4, 'content': '同样的文字', 'time': 1700000000000},
            {'commentId': 5, 'content': '同样的文字', 'time': 1699999999000},
            {'commentId': 5, 'content': '同样的文字', 'time': 1699999999000},
          ],
          'hasMore': true,
        },
      }, '/user/comment/history');
      expect(result.rows.length, 2);
      expect(result.cursor, 1699999999000);
      expect(result.more, true);
      expect(
        NeteaseContent.parse({'events': [], 'more': true}, '/user/event').more,
        false,
      );
      expect(
        NeteaseContent.parse({
          'lasttime': 123456,
          'count': 1,
        }, '/anything').facts.containsKey('上一页时间'),
        false,
      );
      expect(neteaseDisplayTime(null), '');
      expect(neteaseDisplayTime(1700000000000), contains('2023-'));
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'social card and effect options fit compact large text ${brightness.name}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 840));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 840),
                  textScaler: TextScaler.linear(1.6),
                  disableAnimations: true,
                ),
                child: Scaffold(
                  body: RepaintBoundary(
                    key: uiFixCaptureKey,
                    child: ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        NeteaseSocialCard(
                          row: NeteaseContentRow(
                            id: '1',
                            title: '分享音乐和生活里的每个片刻',
                            kind: 'event',
                            raw: {
                              'user': {'nickname': '音乐爱好者'},
                              'time': 1700000000000,
                              'info': {'likedCount': 12, 'commentCount': 3},
                            },
                          ),
                        ),
                        const ProfileEffectPicker(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await captureUiFix(tester, '193-social-effects-${brightness.name}');
      },
    );
  }
}
