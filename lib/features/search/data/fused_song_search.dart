import 'dart:async';
import 'package:http/http.dart' as http;
import '../../../shared/models/track.dart';
import '../../music_platform/data/platform_search_repository.dart';
import '../../music_platform/data/music_platform_api.dart';
import '../../../shared/models/song_search_facts.dart';
import 'song_search_ranking.dart';
import 'song_search_work.dart';

/// A complete view of the pages fetched so far. Cumulative publication lets a
/// later preferred-platform match absorb an earlier supplementary row safely.
class FusedSongSearchPage extends PlatformSearchPage {
  FusedSongSearchPage(
    super.tracks,
    super.total,
    super.hasMore,
    this.sources,
    this.warnings, {
    super.facts = const {},
  });
  final Map<String, List<Track>> sources;
  final List<String> warnings;
}

String _text(String value) => value
    .toLowerCase()
    .replaceAll('（', '(')
    .replaceAll('）', ')')
    .replaceAll(RegExp(r'\s+'), '')
    .trim();

/// Keep version words and artist identity. Title-only or fuzzy matching would
/// incorrectly hide covers, live takes, instrumental tracks and remasters.
bool sameSearchRecording(Track a, Track b) =>
    a.source != b.source &&
    a.title.trim().isNotEmpty &&
    a.artist.trim().isNotEmpty &&
    _text(a.title) == _text(b.title) &&
    _text(a.artist) == _text(b.artist) &&
    a.duration > Duration.zero &&
    b.duration > Duration.zero &&
    (a.duration.inMilliseconds - b.duration.inMilliseconds).abs() <= 2000;

FusedSongSearchPage groupSongSearchResults(
  List<Track> preferred,
  List<Track> supplementary, {
  required bool hasMore,
  List<String> warnings = const [],
  Map<String, SongSearchFacts> facts = const {},
  String query = '',
}) {
  facts = identifySearchWork([...preferred, ...supplementary], facts, query);
  final groups = <List<Track>>[];
  final seen = <String>{};
  for (final track in [...preferred, ...supplementary]) {
    if (!seen.add(track.id)) continue;
    final index = groups.indexWhere(
      (group) =>
          !group.any((member) => member.source == track.source) &&
          sameSearchRecording(group.first, track),
    );
    if (index < 0) {
      groups.add([track]);
    } else {
      groups[index].add(track);
    }
  }
  final sources = <String, List<Track>>{};
  // Sort source choices by measured access, retaining current-platform order
  // for ties. A VIP price flag alone never demotes a playable full recording.
  for (final group in groups) {
    final order = {for (var i = 0; i < group.length; i++) group[i].id: i};
    group.sort((a, b) {
      final access = sourceAccessRank(
        facts[a.id]!,
      ).compareTo(sourceAccessRank(facts[b.id]!));
      return access != 0 ? access : order[a.id]!.compareTo(order[b.id]!);
    });
  }
  final order = {for (var i = 0; i < groups.length; i++) groups[i].first.id: i};
  groups.sort((a, b) {
    // Work identity precedes availability and same-title catalogue flags. An
    // unrelated self-composed song must not displace the requested original.
    final original = recordingRank(
      facts[a.first.id]!,
    ).compareTo(recordingRank(facts[b.first.id]!));
    if (original != 0) return original;
    final relevant = songQueryRelevance(
      a.first,
      query,
    ).compareTo(songQueryRelevance(b.first, query));
    if (relevant != 0) return relevant;
    // Preserve source ranking among ordinary results. Availability selects the
    // version of the requested original, rather than hiding restricted songs.
    if (facts[a.first.id]!.workRelation == SearchWorkRelation.original) {
      final access = sourceAccessRank(
        facts[a.first.id]!,
      ).compareTo(sourceAccessRank(facts[b.first.id]!));
      if (access != 0) return access;
    }
    return order[a.first.id]!.compareTo(order[b.first.id]!);
  });
  for (final group in groups) {
    final immutable = List<Track>.unmodifiable(group);
    for (final track in group) {
      sources[track.id] = immutable;
    }
  }
  return FusedSongSearchPage(
    List.unmodifiable(groups.map((g) => g.first)),
    null,
    hasMore,
    Map.unmodifiable(sources),
    List.unmodifiable(warnings),
    facts: Map.unmodifiable(facts),
  );
}

typedef _SearchOutcome = ({
  PlatformSearchPage? page,
  String? warning,
  PlatformSearchRepository? repository,
});

/// Only song search uses this aggregator. Each source advances independently;
/// a failed page is retried at the same offset instead of silently skipped.
/// The controller's account/query generation remains the publication boundary.
class FusedSongSearchRepository extends PlatformSearchRepository {
  FusedSongSearchRepository(
    super.api, {
    required this.primary,
    required this.secondary,
    required this.primaryLabel,
    required this.secondaryLabel,
  });
  final PlatformSearchRepository primary;
  final Future<PlatformSearchRepository> Function() secondary;
  final String primaryLabel, secondaryLabel;
  final _primaryTracks = <Track>[];
  final _secondaryTracks = <Track>[];
  final _facts = <String, SongSearchFacts>{};
  PlatformSearchRepository? _secondaryRepository;
  int _primaryPage = 1, _secondaryPage = 1, _epoch = 0;
  bool _primaryMore = true, _secondaryMore = true;
  String _query = '';

  Future<_SearchOutcome> _request(
    Future<PlatformSearchRepository> repository,
    String label,
    String query,
    int page,
    Future<void>? externalAbort,
  ) async {
    final abort = Completer<void>();
    if (externalAbort != null) {
      unawaited(
        externalAbort.then((_) {
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }
    final timer = Timer(const Duration(seconds: 18), () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final source = await repository.timeout(const Duration(seconds: 6));
      if (abort.isCompleted) throw http.RequestAbortedException();
      final value = await source
          .search(query, page: page, abortTrigger: abort.future)
          .timeout(const Duration(seconds: 18));
      if (abort.isCompleted) throw http.RequestAbortedException();
      return (page: value, warning: null, repository: source);
    } on Object {
      return (page: null, warning: '$label搜索暂时不可用，可重试加载', repository: null);
    } finally {
      timer.cancel();
    }
  }

  @override
  Future<PlatformSearchPage> search(
    String query, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    if (page == 1 || query != _query) {
      _epoch++;
      _query = query;
      _primaryTracks.clear();
      _secondaryTracks.clear();
      _facts.clear();
      _primaryPage = _secondaryPage = 1;
      _primaryMore = _secondaryMore = true;
    }
    final epoch = _epoch;
    var cancelled = false;
    if (abortTrigger != null) {
      unawaited(abortTrigger.then((_) => cancelled = true));
    }
    // Start both reads together. One platform failing must not hide the other.
    final outcomes = await Future.wait<_SearchOutcome>([
      if (_primaryMore)
        _request(
          Future.value(primary),
          primaryLabel,
          query,
          _primaryPage,
          abortTrigger,
        )
      else
        Future.value((page: null, warning: null, repository: null)),
      if (_secondaryMore)
        _request(
          Future.sync(secondary),
          secondaryLabel,
          query,
          _secondaryPage,
          abortTrigger,
        )
      else
        Future.value((page: null, warning: null, repository: null)),
    ]);
    if (cancelled || epoch != _epoch) throw http.RequestAbortedException();
    if (outcomes.every((o) => o.page == null) &&
        outcomes.any((o) => o.warning != null)) {
      throw const MusicPlatformException('歌曲搜索暂时不可用，请重试加载');
    }
    final first = outcomes[0].page, second = outcomes[1].page;
    if (first != null) {
      _mergeFacts(first.facts);
      final progressed = _append(_primaryTracks, first.tracks);
      _primaryPage++;
      _primaryMore = first.hasMore && progressed;
    }
    if (second != null) {
      _mergeFacts(second.facts);
      _secondaryRepository = outcomes[1].repository;
      final progressed = _append(_secondaryTracks, second.tracks);
      _secondaryPage++;
      _secondaryMore = second.hasMore && progressed;
    }
    final inferred = identifySearchWork(
      [..._primaryTracks, ..._secondaryTracks],
      _facts,
      query,
    );
    final ranked = groupSongSearchResults(
      _primaryTracks,
      _secondaryTracks,
      hasMore: _primaryMore || _secondaryMore,
      facts: inferred,
      query: query,
    );
    // Inspect paired options together; six primary-platform variants must not
    // consume the entire budget before the other source's first original.
    final candidates = ranked.tracks
        .where(
          (t) =>
              inferred[t.id]?.workRelation == SearchWorkRelation.original &&
              songQueryRelevance(t, query) == 0,
        )
        .expand((t) => ranked.sources[t.id] ?? [t])
        .where((t) => inferred[t.id]?.access == SearchPlaybackAccess.unknown)
        .take(6)
        .toList();
    // Two bounded batches, three concurrent metadata reads each. Search never
    // fetches audio bytes or starts listening/reporting. Timeout stays unknown.
    for (var start = 0; start < candidates.length; start += 3) {
      await Future.wait(
        candidates.skip(start).take(3).map((track) async {
          final abort = Completer<void>();
          final timer = Timer(const Duration(seconds: 3), () {
            if (!abort.isCompleted) abort.complete();
          });
          if (abortTrigger != null) {
            unawaited(
              abortTrigger.then((_) {
                if (!abort.isCompleted) abort.complete();
              }),
            );
          }
          try {
            final source = _primaryTracks.any((t) => t.id == track.id)
                ? primary
                : _secondaryRepository;
            final inspected = await source
                ?.inspectAvailability(
                  track,
                  inferred[track.id]!,
                  abortTrigger: abort.future,
                )
                .timeout(const Duration(seconds: 3));
            if (inspected != null && epoch == _epoch && !cancelled) {
              _facts[track.id] = inspected;
            }
          } on Object {
            /* Unknown permissions stay visible and retry at playback. */
          } finally {
            timer.cancel();
            if (!abort.isCompleted) abort.complete();
          }
        }),
      );
      if (cancelled || epoch != _epoch) throw http.RequestAbortedException();
    }
    return groupSongSearchResults(
      _primaryTracks,
      _secondaryTracks,
      hasMore: _primaryMore || _secondaryMore,
      warnings: outcomes.map((o) => o.warning).whereType<String>().toList(),
      facts: _facts,
      query: query,
    );
  }

  /// A source that repeats its last page must stop independently. A temporary
  /// failure never reaches this method and therefore retains its retry cursor.
  bool _append(List<Track> target, List<Track> page) {
    final ids = target.map((track) => track.id).toSet();
    final fresh = page.where((track) => ids.add(track.id)).toList();
    target.addAll(fresh);
    return fresh.isNotEmpty;
  }

  /// A repeated catalogue row does not revoke a measured permission in this
  /// same query/account. Query reset or provider disposal clears that evidence.
  void _mergeFacts(Map<String, SongSearchFacts> values) {
    for (final entry in values.entries) {
      final previous = _facts[entry.key];
      _facts[entry.key] =
          entry.value.access == SearchPlaybackAccess.unknown && previous != null
          ? entry.value.withAccess(previous.access, label: previous.accessLabel)
          : entry.value;
    }
  }
}
