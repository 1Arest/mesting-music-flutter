import 'dart:async';
import 'dart:convert';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/themes/personal_style.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/features/lyrics/lyric_timing.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/experience/presentation/immersive_lyrics.dart';
import 'package:mesting_music/features/lyrics/domain/lyrics_document.dart';
import 'package:mesting_music/features/lyrics/lyrics_providers.dart';
import 'package:mesting_music/features/lyrics/presentation/lyric_scroll_preview.dart';
import 'package:mesting_music/features/lyrics/presentation/lyrics_panel.dart';
import 'package:mesting_music/features/lyrics/presentation/lyric_timing_tools.dart';
import 'package:mesting_music/features/experience/presentation/player_content_transition.dart';
import 'package:mesting_music/shared/models/track.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final immersive in [true, false]) {
    for (final synced in [true, false]) {
      testWidgets(
        'normal lyric tap returns to cover without seeking: immersive=$immersive synced=$synced',
        (tester) async {
          var returns = 0;
          final widget = immersive
              ? ImmersiveLyrics(
                  referenceDesign: true,
                  onReturnToCover: () => returns++,
                )
              : LyricsPanel(immersive: true, onReturnToCover: () => returns++);
          final player = await _mount(tester, widget, synced: synced);
          await tester.tap(find.text(_lines.first.text));
          await tester.pumpAndSettle();
          expect(returns, 1);
          expect(player.seeks, isEmpty);
          expect(player.plays, 0);
          expect(find.byType(LyricSeekRow), findsNothing);
        },
      );
    }
    testWidgets(
      'only manually selected lyric text seeks: immersive=$immersive',
      (tester) async {
        var returns = 0;
        final widget = immersive
            ? ImmersiveLyrics(
                referenceDesign: true,
                onReturnToCover: () => returns++,
              )
            : LyricsPanel(immersive: true, onReturnToCover: () => returns++);
        final player = await _mount(tester, widget);
        await _dragLyrics(tester);
        final preview = find.byType(LyricSeekRow);
        final time = tester.widget<LyricSeekRow>(preview).time;
        final line = _lines.singleWhere((line) => line.time == time);
        expect(player.seeks, isEmpty);
        await tester.tap(
          find.descendant(of: preview, matching: find.text(line.text)),
        );
        await tester.pumpAndSettle();
        expect(player.seeks, [time]);
        expect(player.plays, 1);
        expect(returns, 0);
        await tester.tap(find.text(line.text));
        await tester.pumpAndSettle();
        expect(returns, 1);
        expect(player.seeks, [time]);
      },
    );
  }

  test('歌词偏移按歌曲保存，连续操作和重启后恢复，清零仅还原当前歌', () async {
    final first = ProviderContainer();
    final key = lyricTimingKey(_track);
    await first.read(lyricTimingProvider(key).future);
    await Future.wait([
      first.read(lyricTimingProvider(key).notifier).adjust(500),
      first.read(lyricTimingProvider(key).notifier).adjust(500),
    ]);
    expect(first.read(lyricTimingProvider(key)).value, 1000);
    await first
        .read(lyricTimingProvider('netease:other').notifier)
        .adjust(-500);
    first.dispose();
    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    expect(await restored.read(lyricTimingProvider(key).future), 1000);
    expect(
      await restored.read(lyricTimingProvider('netease:other').future),
      -500,
    );
    await restored.read(lyricTimingProvider(key).notifier).reset();
    expect(restored.read(lyricTimingProvider(key)).value, 0);
    expect(restored.read(lyricTimingProvider('netease:other')).value, -500);
  });

  test('正偏移延后歌词时间，负偏移提前，跨零时间保持句子顺序', () async {
    final document = LyricsDocument(lines: _lines, isSynced: true);
    final container = ProviderContainer(
      overrides: [
        currentTrackProvider.overrideWithValue(_track),
        lyricsProvider.overrideWith((ref, path) async => document),
      ],
    );
    addTearDown(container.dispose);
    final timing = lyricTimingProvider(lyricTimingKey(_track));
    final controller = container.read(timing.notifier);
    await controller.adjust(500);
    final delayed = await container.read(currentTimedLyricsProvider.future);
    expect(
      delayed.lines[1].time,
      _lines[1].time + const Duration(milliseconds: 500),
    );
    await controller.adjust(-1000);
    final early = await container.read(currentTimedLyricsProvider.future);
    expect(early.lines.first.time, const Duration(milliseconds: -500));
    expect(early.activeIndexAt(Duration.zero), 0);
  });

  testWidgets('从既有菜单打开底部调整面板，歌词无额外按钮，半秒偏移仍保存', (tester) async {
    final player = await _mount(
      tester,
      const ImmersiveLyrics(referenceDesign: true),
    );
    expect(find.byTooltip('歌词时间调整'), findsNothing);
    await tester.tap(find.text('菜单中的歌词时间调整'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('＋0.5 秒'));
    await tester.pumpAndSettle();
    expect(find.text('+0.5 秒'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭歌词时间调整'));
    await tester.pumpAndSettle();
    await _dragLyrics(tester);
    final selected = tester.widget<LyricSeekRow>(find.byType(LyricSeekRow));
    expect(
      _lines.any(
        (line) =>
            line.time + const Duration(milliseconds: 500) == selected.time,
      ),
      isTrue,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(LyricSeekRow),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(player.seeks, [selected.time]);
    await tester.tap(find.text('菜单中的歌词时间调整'));
    await tester.pumpAndSettle();
    expect(find.text('+0.5 秒'), findsOneWidget);
    await tester.tap(find.text('还原'));
    await tester.pumpAndSettle();
    expect(find.text('0.0 秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('歌词调整弹层从底部出现，关闭时向下收起', (tester) async {
    await _mount(tester, const ImmersiveLyrics(referenceDesign: true));
    await tester.tap(find.text('菜单中的歌词时间调整'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final early = tester.getRect(find.byType(LyricTimingPanel));
    await tester.pump(const Duration(milliseconds: 100));
    final later = tester.getRect(find.byType(LyricTimingPanel));
    expect(later.left, closeTo(early.left, .01));
    expect(later.top, lessThan(early.top));
    await tester.pumpAndSettle();
    final settled = tester.getRect(find.byType(LyricTimingPanel));
    await tester.tap(find.byTooltip('关闭歌词时间调整'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final closing = tester.getRect(find.byType(LyricTimingPanel));
    expect(closing.top, greaterThan(settled.top));
    expect(closing.left, closeTo(settled.left, .01));
    await tester.pumpAndSettle();
    expect(find.byType(LyricTimingPanel), findsNothing);
  });

  testWidgets('封面到歌词只有垂直位移，歌词退出向下而非横向', (tester) async {
    var lyrics = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return PlayerContentTransition(
                axis: Axis.vertical,
                child: Center(
                  key: ValueKey(lyrics),
                  child: Text(lyrics ? '歌词' : '封面'),
                ),
              );
            },
          ),
        ),
      ),
    );
    final coverCenter = tester.getCenter(find.text('封面'));
    update(() => lyrics = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final entering = tester.getCenter(find.text('歌词'));
    expect(entering.dx, closeTo(coverCenter.dx, .01));
    expect(entering.dy, greaterThan(coverCenter.dy));
    await tester.pumpAndSettle();
    final settled = tester.getCenter(find.text('歌词'));
    update(() => lyrics = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final closing = tester.getCenter(find.text('歌词'));
    expect(closing.dx, closeTo(settled.dx, .01));
    expect(closing.dy, greaterThan(settled.dy));
    await tester.pumpAndSettle();
  });

  testWidgets('模糊歌词滚动时提亮居中的换行歌词并按准确时间播放', (tester) async {
    final player = await _mount(
      tester,
      const ImmersiveLyrics(referenceDesign: true),
      scale: 1.7,
    );
    final preview = find.byType(LyricSeekRow);
    expect(preview, findsNothing);

    await _dragLyrics(tester);
    final row = tester.widget<LyricSeekRow>(preview);
    final line = _lines.singleWhere((line) => line.time == row.time);
    expect(row.time, greaterThan(Duration.zero));
    expect(
      find.descendant(of: preview, matching: find.text(line.text)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: preview, matching: find.byType(ImageFiltered)),
      findsNothing,
    );
    expect(
      tester.getRect(preview).contains(tester.getCenter(find.byType(ListView))),
      isTrue,
    );
    expect(
      tester
          .widgetList<ImageFiltered>(find.byType(ImageFiltered))
          .any((filter) => filter.enabled),
      isTrue,
    );
    expect(player.seeks, isEmpty);

    await tester.tap(
      find.descendant(of: preview, matching: find.byType(IconButton)),
    );
    await tester.pumpAndSettle();
    expect(player.seeks, [line.time]);
    expect(player.plays, 1);
    expect(preview, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('个性歌词的字号行距和高亮保留滚动定位播放', (tester) async {
    const style = PersonalStyle(
      lyricSize: 32,
      lineHeight: 1.7,
      lyricColor: 0xFFFFC2D6,
    );
    final player = await _mount(
      tester,
      const ImmersiveLyrics(referenceDesign: true),
      style: style,
    );
    await _dragLyrics(tester);
    final preview = find.byType(LyricSeekRow);
    final row = tester.widget<LyricSeekRow>(preview);
    final line = _lines.singleWhere((line) => line.time == row.time);
    final text = tester.widget<Text>(
      find.descendant(of: preview, matching: find.text(line.text)),
    );
    expect(text.style!.fontSize, 32);
    expect(text.style!.height, 1.7);
    expect(text.style!.color, const Color(0xFFFFC2D6));
    expect(
      tester.getRect(preview).contains(tester.getCenter(find.byType(ListView))),
      isTrue,
    );
    await tester.tap(
      find.descendant(of: preview, matching: find.byType(IconButton)),
    );
    await tester.pumpAndSettle();
    expect(player.seeks, [line.time]);
    expect(player.plays, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('经典歌词浏览期间暂停跟播并在空闲后恢复', (tester) async {
    final positions = StreamController<Duration>.broadcast();
    addTearDown(positions.close);
    final player = await _mount(
      tester,
      const LyricsPanel(immersive: true),
      positions: positions.stream,
    );
    positions.add(Duration.zero);
    await tester.pumpAndSettle();
    await _dragLyrics(tester);

    final preview = find.byType(LyricSeekRow);
    final time = tester.widget<LyricSeekRow>(preview).time;
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final browsedOffset = scrollable.position.pixels;
    positions.add(_lines.last.time);
    await tester.pumpAndSettle();
    expect(tester.widget<LyricSeekRow>(preview).time, time);
    expect(scrollable.position.pixels, browsedOffset);
    expect(player.seeks, isEmpty);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(preview, findsNothing);
    expect(scrollable.position.pixels, greaterThan(browsedOffset));
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有时间戳的歌词可滚动但不提供定位按钮', (tester) async {
    final player = await _mount(
      tester,
      const ImmersiveLyrics(referenceDesign: true),
      synced: false,
    );
    await _dragLyrics(tester);
    expect(find.byType(LyricSeekRow), findsNothing);
    expect(player.seeks, isEmpty);
  });
}

Future<void> _dragLyrics(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ListView)),
  );
  await gesture.moveBy(const Offset(0, -24));
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.moveBy(const Offset(0, -146));
  await tester.pump(const Duration(milliseconds: 180));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<_Player> _mount(
  WidgetTester tester,
  Widget lyrics, {
  Stream<Duration>? positions,
  double scale = 1,
  bool synced = true,
  PersonalStyle? style,
}) async {
  final preferences = await SharedPreferences.getInstance();
  if (style != null) {
    await preferences.setString(
      PersonalStyleController.preferenceKey,
      jsonEncode(style.toJson()),
    );
  }
  final player = _Player();
  final document = LyricsDocument(lines: _lines, isSynced: synced);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        audioHandlerProvider.overrideWithValue(player),
        currentTrackProvider.overrideWithValue(_track),
        lyricsProvider.overrideWith((ref, path) async => document),
        positionProvider.overrideWith(
          (ref) => positions ?? Stream.value(Duration.zero),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => showLyricTimingSheet(context),
                  child: const Text('菜单中的歌词时间调整'),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.black,
          body: Center(
            child: SizedBox(
              width: 340,
              height: 400,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: lyrics,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return player;
}

class _Player extends Fake implements MestingAudioHandler {
  final seeks = <Duration>[];
  int plays = 0;

  @override
  int get transportRevision => seeks.length + plays;

  @override
  Future<void> seek(Duration position, {bool Function()? togetherGuard}) async {
    seeks.add(position);
  }

  @override
  Future<void> play({bool Function()? togetherGuard}) async {
    plays++;
  }
}

const _track = Track(
  id: 'scroll-preview',
  title: '歌词定位',
  artist: 'Mesting',
  album: '',
  duration: Duration(minutes: 3),
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: 'scroll-preview.lrc',
);

final _lines = List.generate(
  20,
  (index) => LyricsLine(
    time: Duration(milliseconds: index * 10037),
    text: index.isEven ? '歌词 ${index + 1}' : '换行测试 ${index + 1} 这里是一句更长的同步歌词',
  ),
);
