import '../../../shared/widgets/music_list_footer.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/music_refresh_indicator.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../../experience/presentation/editorial_widgets.dart';
import '../data/platform_recommendations.dart';
import '../music_platform_providers.dart';
import '../platform_backend_providers.dart';
import '../platform_catalog_providers.dart';
import '../platform_recommendation_providers.dart';
import '../platform_browse_cache.dart';
import 'retained_platform_snapshot.dart';
import '../../auth/presentation/beta_login_navigation.dart';
import 'platform_design.dart';
import 'platform_feedback.dart';
import '../../../shared/widgets/automatic_song_paging.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../../player/presentation/beta_playback_actions.dart';

/// Original md3Music's four discovery modules, rendered in the approved Mesting
/// visual language. Platform providers own ordering and provenance, not widgets.
class PlatformRecommendationHome extends ConsumerWidget {
  const PlatformRecommendationHome({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PlatformStyle(
    child: EditorialScroll(
      onRefresh: () => refreshBrowse(ref, [
        if (ref.exists(platformFmProvider))
          () => ref.refresh(platformFmProvider.future),
        if (ref.exists(platformDailyProvider))
          () => ref.refresh(platformDailyProvider.future),
        if (ref.exists(platformDiscoveryProvider))
          () => ref.refresh(platformDiscoveryProvider.future),
        if (ref.exists(platformNewSongsProvider))
          () => ref.refresh(platformNewSongsProvider.future),
      ]),
      children: const [
        EditorialHeader('发现'),
        PlatformFmSection(),
        PlatformRecommendedSection(title: '每日推荐'),
        PlatformRecommendedSection(
          title: '刷歌推荐',
          kind: PlatformRecommendationKind.discover,
        ),
        PlatformRecommendedSection(title: '新歌速递', newSongs: true),
      ],
    ),
  );
}

class PlatformFmSection extends ConsumerWidget {
  const PlatformFmSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(platformAccountProvider).value != null;
    final station = ref.watch(platformFmStationProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorialSection(
          '私人 FM',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const PlatformRecommendationDetail(
                kind: PlatformRecommendationKind.fm,
                title: '私人 FM',
              ),
            ),
          ),
        ),
        if (!signedIn)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: TextButton.icon(
              onPressed: () => openBetaLogin(context, redirect: '/music'),
              icon: const Icon(Icons.login),
              label: const Text('登录酷狗后查看猜你喜欢和实时推荐'),
            ),
          )
        else ...[
          if (!ref.watch(usesNeteaseProvider))
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final option in PlatformFmStation.values)
                    ChoiceChip(
                      label: Text(option.label),
                      selected: station == option,
                      onSelected: (_) => ref
                          .read(platformFmStationProvider.notifier)
                          .select(option),
                    ),
                ],
              ),
            ),
          const PlatformRecommendedSection(
            title: '',
            kind: PlatformRecommendationKind.fm,
          ),
        ],
      ],
    );
  }
}

class PlatformRecommendedSection extends ConsumerWidget {
  const PlatformRecommendedSection({
    required this.title,
    this.kind,
    this.newSongs = false,
    super.key,
  });
  final String title;
  final PlatformRecommendationKind? kind;
  final bool newSongs;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = kind == PlatformRecommendationKind.fm
        ? platformFmProvider
        : kind == PlatformRecommendationKind.discover
        ? platformDiscoveryProvider
        : newSongs
        ? platformNewSongsProvider
        : platformDailyProvider;
    final value = ref.watch(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title.isNotEmpty)
          EditorialSection(
            title,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PlatformRecommendationDetail(
                  kind: kind,
                  title: title,
                  newSongs: newSongs,
                ),
              ),
            ),
          ),
        RetainedPlatformSnapshot(
          value: value,
          artwork: (tracks) => tracks.map((track) => track.coverAsset),
          loading: () => const PlatformFeedbackState(loading: true),
          error: (_, _) => EditorialEmpty(
            '暂时无法获取推荐',
            onRetry: () => ref.invalidate(provider),
          ),
          data: (tracks) => tracks.isEmpty
              ? EditorialEmpty(
                  '平台暂未返回内容',
                  onRetry: () => ref.invalidate(provider),
                )
              : Column(
                  children: [
                    for (final track in tracks.take(4))
                      EditorialTrackRow(
                        track: track,
                        contextTracks: tracks,
                        onPlay: () => _play(
                          context,
                          ref,
                          tracks,
                          tracks.indexOf(track),
                          kind,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

Future<void> _play(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks,
  int index,
  PlatformRecommendationKind? kind,
) async {
  try {
    if (kind != null) {
      if (await playBetaSelection(context, ref, tracks[index])) {
        ref
            .read(platformRecommendationSessionProvider)
            .adoptCurrent(kind, tracks[index]);
      }
    } else {
      await playEditorialTrack(context, ref, tracks[index], tracks);
    }
  } catch (error) {
    if (context.mounted) showPlatformFailure(context, error);
  }
}

class PlatformRecommendationDetail extends ConsumerStatefulWidget {
  const PlatformRecommendationDetail({
    required this.title,
    this.kind,
    this.newSongs = false,
    super.key,
  });
  final String title;
  final PlatformRecommendationKind? kind;
  final bool newSongs;
  @override
  ConsumerState<PlatformRecommendationDetail> createState() =>
      _PlatformRecommendationDetailState();
}

class _PlatformRecommendationDetailState
    extends ConsumerState<PlatformRecommendationDetail> {
  final _extra = <Track>[];
  int _fixedVisible = 30;
  List<Track>? _mergedBase;
  List<Track> _mergedSnapshot = const [];
  int _mergedExtraCount = -1, _mergedGeneration = -1;
  bool _loading = false, _more = true;
  String? _error;
  String? _baseSignature;
  int _generation = 0;
  Set<String> _baseIds = {};
  List<Track>? _initialBase;
  bool _firstScreenReady = false, _preparingFirstScreen = false;
  String? _initialError;

  /// The FM preview is a small upstream batch, not a complete detail page.
  /// Stage enough unique recordings for the viewport, then publish once. A
  /// bounded loop and the no-progress check also handle exhausted/duplicate
  /// recommendations without an endless spinner or changing upstream order.
  Future<void> _prepareFirstScreen(List<Track> base, int minimum) async {
    final generation = _generation;
    final repository = ref.read(platformRecommendationsProvider);
    final station = ref.read(platformFmStationProvider);
    final staged = <Track>[];
    final ids = base.map((track) => track.id).toSet();
    var more = base.isNotEmpty;
    try {
      for (
        var request = 0;
        ids.length < minimum && more && request < 6;
        request++
      ) {
        final next = await repository.personalFm(
          station,
          first: false,
          anchor: staged.lastOrNull ?? base.lastOrNull,
        );
        if (!mounted || generation != _generation) return;
        final additions = next.where((track) => ids.add(track.id)).toList();
        staged.addAll(additions);
        more = additions.isNotEmpty;
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _extra.addAll(staged);
        _more = more;
        _firstScreenReady = true;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _initialError = '推荐暂时无法读取');
      }
    } finally {
      if (mounted && generation == _generation) {
        _preparingFirstScreen = false;
      }
    }
  }

  void _resetFirstScreen() {
    _initialBase = null;
    _firstScreenReady = false;
    _preparingFirstScreen = false;
    _initialError = null;
  }

  Future<void> _load() async {
    if (_loading || !_more) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(platformRecommendationsProvider);
      final fresh = widget.kind == PlatformRecommendationKind.fm
          ? await repository.personalFm(
              ref.read(platformFmStationProvider),
              first: false,
              anchor: _extra.lastOrNull ?? _initialBase?.lastOrNull,
            )
          : await repository.discover(more: true);
      if (!mounted || generation != _generation) return;
      setState(() {
        final ids = {..._baseIds, ..._extra.map((e) => e.id)};
        final additions = fresh.where((e) => ids.add(e.id)).toList();
        _extra.addAll(additions);
        _more = additions.isNotEmpty;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '加载失败，点击重试');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.kind == PlatformRecommendationKind.fm
        ? platformFmProvider
        : widget.kind == PlatformRecommendationKind.discover
        ? platformDiscoveryProvider
        : widget.newSongs
        ? platformNewSongsProvider
        : platformDailyProvider;
    final value = ref.watch(provider);
    final signature =
        '${ref.watch(platformAccountProvider).value?.userId}:${ref.watch(platformFmStationProvider).name}';
    if (_baseSignature != signature) {
      _baseSignature = signature;
      _generation++;
      _loading = false;
      _extra.clear();
      _more = true;
      _resetFirstScreen();
    }
    return PlatformPageFrame(
      title: widget.title,
      child: value.when(
        skipLoadingOnRefresh: false,
        loading: () => const _RecommendationLoading(),
        error: (_, _) =>
            EditorialEmpty('推荐暂时无法读取', onRetry: () => ref.invalidate(provider)),
        data: (base) {
          if (widget.kind == PlatformRecommendationKind.fm &&
              !identical(base, _initialBase)) {
            _generation++;
            _extra.clear();
            _loading = false;
            _more = true;
            _resetFirstScreen();
            _initialBase = base;
          }
          if (widget.kind == PlatformRecommendationKind.fm &&
              !_firstScreenReady) {
            return LayoutBuilder(
              builder: (context, constraints) {
                if (_initialError != null) {
                  return EditorialEmpty(
                    _initialError!,
                    onRetry: () {
                      setState(() {
                        _generation++;
                        _resetFirstScreen();
                      });
                      ref.invalidate(provider);
                    },
                  );
                }
                if (!_preparingFirstScreen) {
                  _preparingFirstScreen = true;
                  // Rows are at least 70dp (52dp artwork + 18dp padding).
                  // Reserve the same 180dp as the list for floating controls.
                  // At larger text sizes fewer rows fit, so this is conservative.
                  final minimum = ((constraints.maxHeight - 180) / 70)
                      .ceil()
                      .clamp(1, 40);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && identical(_initialBase, base)) {
                      unawaited(_prepareFirstScreen(base, minimum));
                    }
                  });
                }
                return const _RecommendationLoading();
              },
            );
          }
          // Revealing thirty more rows must not re-index a fixed response of
          // thousands of songs. Only a changed source snapshot/FM batch does.
          if (!identical(base, _mergedBase) ||
              _extra.length != _mergedExtraCount ||
              _mergedGeneration != _generation) {
            _mergedBase = base;
            _mergedExtraCount = _extra.length;
            _mergedGeneration = _generation;
            _mergedSnapshot = <String, Track>{
              for (final t in [...base, ..._extra]) t.id: t,
            }.values.toList();
            _baseIds = base.map((track) => track.id).toSet();
          }
          final tracks = _mergedSnapshot;
          final visibleCount = widget.kind == null
              ? _fixedVisible.clamp(0, tracks.length)
              : tracks.length;
          return MusicRefreshIndicator(
            onRefresh: () async {
              setState(() {
                _generation++;
                _loading = false;
                _extra.clear();
                _more = true;
                _resetFirstScreen();
              });
              ref.invalidate(provider);
              await ref.read(provider.future);
            },
            child: AutomaticSongPaging(
              fillInitialViewport: widget.kind != PlatformRecommendationKind.fm,
              enabled: widget.kind == null
                  ? visibleCount < tracks.length
                  : _more && !_loading && _error == null,
              onLoadMore: widget.kind == null
                  ? () async {
                      if (mounted) setState(() => _fixedVisible += 30);
                    }
                  : _load,
              child: ListView.builder(
                cacheExtent: MediaQuery.sizeOf(context).height,
                padding: BetaContentInsets.musicPaddingOf(
                  context,
                  EdgeInsets.only(bottom: 180),
                ),
                itemCount: visibleCount + 1,
                itemBuilder: (context, index) {
                  if (index < visibleCount) {
                    return EditorialTrackRow(
                      track: tracks[index],
                      contextTracks: tracks,
                      onPlay: () =>
                          _play(context, ref, tracks, index, widget.kind),
                    );
                  }
                  if (_loading) {
                    return const _RecommendationLoading();
                  }
                  if (_error != null) {
                    return TextButton(onPressed: _load, child: Text(_error!));
                  }
                  if (tracks.isEmpty) return const EditorialEmpty('平台暂未返回歌曲');
                  return (widget.kind != null && _more) ||
                          visibleCount < tracks.length
                      ? const SizedBox(height: 12)
                      : const MusicListEnd();
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// List loading keeps the page's own background visible, including the footer.
class _RecommendationLoading extends StatelessWidget {
  const _RecommendationLoading();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 32),
    child: Center(child: MestingLoadingIndicator(semanticLabel: '正在加载音乐内容')),
  );
}
