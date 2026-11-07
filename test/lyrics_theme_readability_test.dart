import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:math_curve_loaders/math_curve_loaders.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/lyrics/domain/lyrics_document.dart';
import 'package:mesting_music/features/lyrics/lyrics_providers.dart';
import 'package:mesting_music/features/lyrics/presentation/lyrics_panel.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/models/track.dart';

void main() {
  const track = Track(
    id: 'lyrics-readability',
    title: '主题歌词',
    artist: 'Mesting',
    album: '',
    duration: Duration(minutes: 3),
    audioAsset: '',
    coverAsset: '',
    lyricsAsset: 'test-lyrics.lrc',
  );
  const document = LyricsDocument(
    isSynced: true,
    lines: [
      LyricsLine(time: Duration.zero, text: '已经唱过的歌词'),
      LyricsLine(time: Duration(seconds: 10), text: '正在唱的歌词'),
      LyricsLine(time: Duration(seconds: 20), text: '还没有唱的歌词'),
    ],
  );

  Future<void> pumpLyrics(WidgetTester tester, MusicThemePreset preset) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentTrackProvider.overrideWithValue(track),
          positionProvider.overrideWith(
            (ref) => Stream.value(const Duration(seconds: 15)),
          ),
          lyricsProvider.overrideWith((ref, path) async => document),
        ],
        child: MaterialApp(
          theme: buildMestingTheme(preset),
          home: const Scaffold(body: LyricsPanel(immersive: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AnimatedDefaultTextStyle lineStyle(WidgetTester tester, int index) {
    return tester.widget<AnimatedDefaultTextStyle>(
      find.byKey(ValueKey('lyrics-line-$index-style')),
    );
  }

  testWidgets('light image themes keep completed and upcoming lyrics legible', (
    tester,
  ) async {
    final preset = musicThemePresetById('sunset-road');
    await pumpLyrics(tester, preset);

    expect(lineStyle(tester, 0).style.color, const Color(0x8FFFFFFF));
    expect(lineStyle(tester, 1).style.color, Colors.white);
    expect(lineStyle(tester, 2).style.color, const Color(0xA8FFFFFF));
    expect(lineStyle(tester, 0).style.shadows, isNotEmpty);
    expect(lineStyle(tester, 1).style.shadows, isNotEmpty);
    expect(
      lineStyle(tester, 1).style.shadows?.first.color,
      const Color(0xE6000000),
    );
  });

  testWidgets('dark image themes use the same readable lyric hierarchy', (
    tester,
  ) async {
    final preset = musicThemePresetById('starry-radio');
    await pumpLyrics(tester, preset);

    expect(lineStyle(tester, 0).style.color, const Color(0x8FFFFFFF));
    expect(lineStyle(tester, 1).style.color, Colors.white);
    expect(lineStyle(tester, 2).style.color, const Color(0xA8FFFFFF));
    expect(
      lineStyle(tester, 2).style.shadows?.first.color,
      const Color(0xE6000000),
    );
  });

  testWidgets('歌词载入使用李萨如曲线并移除原生转圈', (tester) async {
    final pendingLyrics = Completer<LyricsDocument>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentTrackProvider.overrideWithValue(track),
          positionProvider.overrideWith(
            (ref) => Stream.value(const Duration(seconds: 15)),
          ),
          lyricsProvider.overrideWith((ref, path) => pendingLyrics.future),
        ],
        child: MaterialApp(
          theme: buildMestingTheme(musicThemePresetById('classic-dark')),
          home: const Scaffold(body: LyricsPanel(immersive: true)),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('lyrics-curve-loader')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('正在铺开歌词'), findsNothing);
    expect(find.bySemanticsLabel('正在加载歌词'), findsOneWidget);

    final loader = tester.widget<MathCurveLoader>(find.byType(MathCurveLoader));
    expect(loader.duration, const Duration(milliseconds: 3000));
    expect(loader.respectReducedMotion, isTrue);
    expect(loader.style.particleCount, 62);
    expect(loader.style.trailSpan, .34);

    pendingLyrics.complete(document);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyrics-curve-loader')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
