import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/core/audio/queue_engine.dart';
import 'package:mesting_music/features/queue/presentation/queue_page.dart';
import 'package:flutter/material.dart';

void main() {
  group('QueueEngine', () {
    test('播放模式切换时使用对应图标', () {
      expect(playbackModeIcon(PlaybackMode.list), Icons.repeat_rounded);
      expect(playbackModeIcon(PlaybackMode.single), Icons.repeat_one_rounded);
      expect(playbackModeIcon(PlaybackMode.random), Icons.shuffle_rounded);
    });

    test('播放列表抽屉从空列表的紧凑高度随歌曲数量增长并在大列表时封顶', () {
      expect(playbackQueueSheetHeightFactor, .74);
      expect(minimumPopulatedQueueSheetHeightFactor, .30);
      expect(
        emptyPlaybackQueueSheetHeightFactor,
        minimumPopulatedQueueSheetHeightFactor,
      );
      expect(
        emptyPlaybackQueueSheetHeightFactor,
        lessThan(playbackQueueSheetHeightFactor),
      );
      expect(playbackQueueRowHeight, 64);

      final oneTrack = playbackQueueSheetHeightFactorForCount(
        count: 1,
        viewportHeight: 800,
        bottomInset: 24,
      );
      final twoTracks = playbackQueueSheetHeightFactorForCount(
        count: 2,
        viewportHeight: 800,
        bottomInset: 24,
      );
      final sixTracks = playbackQueueSheetHeightFactorForCount(
        count: 6,
        viewportHeight: 800,
        bottomInset: 24,
      );
      final manyTracks = playbackQueueSheetHeightFactorForCount(
        count: 30,
        viewportHeight: 800,
        bottomInset: 24,
      );

      expect(oneTrack, minimumPopulatedQueueSheetHeightFactor);
      expect(twoTracks, greaterThan(oneTrack));
      expect(twoTracks, lessThan(.4));
      expect(sixTracks, greaterThan(twoTracks));
      expect(manyTracks, playbackQueueSheetHeightFactor);
      expect(
        playbackQueueSheetHeightFactorForCount(
          count: 0,
          viewportHeight: 800,
          bottomInset: 24,
        ),
        oneTrack,
      );
    });

    test('待播放队列从当前歌曲之后开始并在末尾接回开头', () {
      expect(
        QueueEngine.upcomingAfter(<String>['A', 'B', 'C', 'D'], 1),
        <String>['C', 'D', 'A'],
      );
    });

    test('当前歌曲是唯一歌曲时待播放队列为空', () {
      expect(QueueEngine.upcomingAfter(<String>['A'], 0), isEmpty);
    });

    test('播放确认后只从待播数据移除当前曲目', () {
      expect(
        QueueEngine.withoutId(
          <String>['B', 'A', 'C', 'A'],
          'A',
          idOf: (item) => item,
        ),
        <String>['B', 'C'],
      );
      expect(
        QueueEngine.keepCurrentAndRemoveDuplicate(
          <String>['A', 'B', 'A', 'C'],
          'A',
          idOf: (item) => item,
        ),
        <String>['A', 'B', 'C'],
      );
    });

    test('单曲追加只判断点击歌曲并阻止当前曲或重复项', () {
      expect(
        QueueEngine.canAppendTrack(
          candidateId: '夜曲',
          currentId: '晴天',
          upcomingIds: const ['七里香', '花海'],
        ),
        isTrue,
      );
      expect(
        QueueEngine.canAppendTrack(
          candidateId: '夜曲',
          currentId: '晴天',
          upcomingIds: const ['七里香', '夜曲'],
        ),
        isFalse,
      );
      expect(
        QueueEngine.canAppendTrack(
          candidateId: '晴天',
          currentId: '晴天',
          upcomingIds: const ['七里香'],
        ),
        isFalse,
      );
    });

    test('待播列表按模式选择下一首，顺序取首项而随机落在剩余范围内', () {
      expect(
        QueueEngine.resolveUpcomingIndex(length: 4, mode: PlaybackMode.list),
        0,
      );
      expect(
        QueueEngine.resolveUpcomingIndex(length: 4, mode: PlaybackMode.single),
        0,
      );
      expect(
        QueueEngine.resolveUpcomingIndex(
          length: 4,
          mode: PlaybackMode.random,
          random: Random(7),
        ),
        inInclusiveRange(0, 3),
      );
    });

    test('自动随机续播避开当前歌曲和最近播放窗口', () {
      final target = QueueEngine.resolveFallbackIndex(
        candidateIds: const ['A', 'B', 'C', 'D', 'E'],
        recentIds: const ['A', 'B', 'C'],
        currentId: 'C',
        avoidRecent: true,
        mode: PlaybackMode.random,
        forward: true,
        random: Random(7),
      );

      expect(target, anyOf(3, 4));
    });

    test('手动切歌不受最近播放窗口限制但不会立即重复当前歌曲', () {
      final target = QueueEngine.resolveFallbackIndex(
        candidateIds: const ['A', 'B', 'C'],
        recentIds: const ['A', 'B', 'C'],
        currentId: 'C',
        avoidRecent: false,
        mode: PlaybackMode.list,
        forward: true,
      );

      expect(target, 0);
    });

    test('曲库小于防重复窗口时会逐步放宽但仍优先避开当前歌曲', () {
      final target = QueueEngine.resolveFallbackIndex(
        candidateIds: const ['A', 'B'],
        recentIds: const ['A', 'B'],
        currentId: 'B',
        avoidRecent: true,
        mode: PlaybackMode.list,
        forward: true,
      );

      expect(target, 0);
    });

    test('未启用自动续播随机化时仍可按来源顺序解析候选', () {
      expect(
        QueueEngine.resolveFallbackIndex(
          candidateIds: const ['A', 'B', 'C'],
          recentIds: const [],
          currentId: 'B',
          avoidRecent: false,
          mode: PlaybackMode.list,
          forward: true,
        ),
        2,
      );
      expect(
        QueueEngine.resolveFallbackIndex(
          candidateIds: const ['A', 'B', 'C'],
          recentIds: const [],
          currentId: 'B',
          avoidRecent: false,
          mode: PlaybackMode.list,
          forward: false,
        ),
        0,
      );
    });

    test('待播队列为空时可强制随机自动续播而不沿用来源顺序', () {
      final target = QueueEngine.resolveFallbackIndex(
        candidateIds: const ['A', 'B', 'C', 'D'],
        recentIds: const [],
        currentId: 'A',
        avoidRecent: true,
        mode: PlaybackMode.list,
        forward: true,
        randomize: true,
        random: _LastChoiceRandom(),
      );

      expect(target, 3);
    });

    test('列表循环首尾相接', () {
      expect(
        QueueEngine.nextIndex(
          length: 3,
          currentIndex: 2,
          mode: PlaybackMode.list,
        ),
        0,
      );
      expect(
        QueueEngine.previousIndex(
          length: 3,
          currentIndex: 0,
          mode: PlaybackMode.list,
        ),
        2,
      );
    });

    test('单曲循环保持当前索引', () {
      expect(
        QueueEngine.nextIndex(
          length: 4,
          currentIndex: 2,
          mode: PlaybackMode.single,
        ),
        2,
      );
    });

    test('随机播放不会立刻重复当前歌曲', () {
      final target = QueueEngine.nextIndex(
        length: 5,
        currentIndex: 2,
        mode: PlaybackMode.random,
        random: Random(7),
      );

      expect(target, isNot(2));
      expect(target, inInclusiveRange(0, 4));
    });

    test('空队列和单曲队列安全返回零', () {
      expect(
        QueueEngine.nextIndex(
          length: 0,
          currentIndex: 0,
          mode: PlaybackMode.list,
        ),
        0,
      );
      expect(
        QueueEngine.previousIndex(
          length: 1,
          currentIndex: 0,
          mode: PlaybackMode.random,
        ),
        0,
      );
    });

    test(
      'restored single-track pool never resolves a skip to the current track',
      () {
        for (final mode in PlaybackMode.values) {
          expect(
            QueueEngine.resolveFallbackIndex(
              candidateIds: const ['current'],
              recentIds: const ['current'],
              currentId: 'current',
              avoidRecent: true,
              mode: mode,
              forward: true,
            ),
            -1,
          );
        }
      },
    );
  });
}

class _LastChoiceRandom implements Random {
  @override
  bool nextBool() => true;

  @override
  double nextDouble() => .999999;

  @override
  int nextInt(int max) => max - 1;
}
