import 'dart:math';

import 'playback_mode.dart';

class QueueEngine {
  const QueueEngine._();

  static List<T> withoutId<T>(
    Iterable<T> items,
    String id, {
    required String Function(T item) idOf,
  }) {
    return items.where((item) => idOf(item) != id).toList(growable: false);
  }

  static List<T> keepCurrentAndRemoveDuplicate<T>(
    Iterable<T> items,
    String currentId, {
    required String Function(T item) idOf,
  }) {
    var keptCurrent = false;
    return items
        .where((item) {
          if (idOf(item) != currentId) return true;
          if (keptCurrent) return false;
          keptCurrent = true;
          return true;
        })
        .toList(growable: false);
  }

  static List<T> upcomingAfter<T>(List<T> items, int currentIndex) {
    if (items.length <= 1) return <T>[];
    final safeIndex = currentIndex.clamp(0, items.length - 1);
    return <T>[...items.skip(safeIndex + 1), ...items.take(safeIndex)];
  }

  static bool canAppendTrack({
    required String candidateId,
    required String? currentId,
    required Iterable<String> upcomingIds,
  }) {
    if (candidateId == currentId) return false;
    return !upcomingIds.contains(candidateId);
  }

  static int resolveUpcomingIndex({
    required int length,
    required PlaybackMode mode,
    Random? random,
  }) {
    if (length <= 0) return -1;
    if (mode != PlaybackMode.random) return 0;
    return (random ?? Random()).nextInt(length);
  }

  static int resolveFallbackIndex({
    required List<String> candidateIds,
    required Iterable<String> recentIds,
    required String? currentId,
    required bool avoidRecent,
    required PlaybackMode mode,
    required bool forward,
    bool randomize = false,
    Random? random,
  }) {
    if (candidateIds.isEmpty) return -1;
    final recent = recentIds.toSet();
    var eligible = <int>[
      for (var index = 0; index < candidateIds.length; index += 1)
        if (candidateIds[index] != currentId &&
            (!avoidRecent || !recent.contains(candidateIds[index])))
          index,
    ];

    // A small catalogue can temporarily exhaust the recent-play window.
    // Relax that window before ever repeating the currently playing song.
    if (eligible.isEmpty) {
      eligible = <int>[
        for (var index = 0; index < candidateIds.length; index += 1)
          if (candidateIds[index] != currentId) index,
      ];
    }
    // A skip must never resolve back to the item that is already playing.
    // Returning no candidate lets the audio handler discover a fresh online
    // fallback instead of silently reloading the same restored single track.
    if (eligible.isEmpty) return -1;
    if (randomize || mode == PlaybackMode.random) {
      return eligible[(random ?? Random()).nextInt(eligible.length)];
    }

    final eligibleSet = eligible.toSet();
    final currentIndex = currentId == null
        ? -1
        : candidateIds.indexOf(currentId);
    if (currentIndex < 0) {
      return forward ? eligible.first : eligible.last;
    }
    for (var offset = 1; offset <= candidateIds.length; offset += 1) {
      final candidate = forward
          ? (currentIndex + offset) % candidateIds.length
          : (currentIndex - offset + candidateIds.length) % candidateIds.length;
      if (eligibleSet.contains(candidate)) return candidate;
    }
    return eligible.first;
  }

  static int nextIndex({
    required int length,
    required int currentIndex,
    required PlaybackMode mode,
    Random? random,
  }) {
    if (length <= 1) return 0;
    if (mode == PlaybackMode.single) return currentIndex.clamp(0, length - 1);
    if (mode == PlaybackMode.random) {
      final generator = random ?? Random();
      var candidate = generator.nextInt(length - 1);
      if (candidate >= currentIndex) candidate += 1;
      return candidate;
    }
    return (currentIndex + 1) % length;
  }

  static int previousIndex({
    required int length,
    required int currentIndex,
    required PlaybackMode mode,
    Random? random,
  }) {
    if (length <= 1) return 0;
    if (mode == PlaybackMode.single) return currentIndex.clamp(0, length - 1);
    if (mode == PlaybackMode.random) {
      return nextIndex(
        length: length,
        currentIndex: currentIndex,
        mode: mode,
        random: random,
      );
    }
    return (currentIndex - 1 + length) % length;
  }
}
