import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../player/presentation/beta_playback_actions.dart';
import '../data/platform_explore.dart';
import '../data/platform_ranking.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';
import '../platform_backend_providers.dart';
import '../platform_explore_providers.dart';
import 'platform_feedback.dart';

/// One selection counter plus account checks coordinate card play requests. If the
/// user taps another card while this one is loading, only the newer selection
/// may replace playback. A widget disappearing also cancels publication.
final collectionPlayIntentProvider = Provider((ref) => CollectionPlayIntent());

class CollectionPlayIntent {
  int _generation = 0;
  int begin() => ++_generation;
  bool owns(int value) => value == _generation;
}

Future<List<Track>> completePublicCollection(
  WidgetRef ref,
  PlatformExploreItem item,
  bool Function() isCurrent,
) async {
  final owner = ref.read(platformAccountProvider).value;
  if (owner == null) throw StateError('请先登录音乐平台');
  final repository = PlatformRankingRepository(
    api: ref.read(musicPlatformApiProvider),
    owner: owner,
    isCurrent: isCurrent,
    netease: owner.platform == MusicPlatform.netease
        ? ref.read(neteaseMusicRepositoryProvider)
        : null,
  );
  var edition = item;
  if (item.kind == PlatformExploreKind.rank &&
      owner.platform == MusicPlatform.kugou) {
    final info = await repository.info(item);
    edition = PlatformExploreItem(
      id: item.id,
      title: item.title,
      cover: item.cover,
      kind: item.kind,
      rankCid: info.period,
    );
  }
  return repository.complete(
    ref.read(platformExploreRepositoryProvider),
    edition,
  );
}

/// This is a sibling hit target above the cover. The enclosing card continues
/// to navigate, while this control reads the entire collection before playing.
class PlatformCollectionPlayButton extends ConsumerStatefulWidget {
  const PlatformCollectionPlayButton({required this.item, super.key});
  final PlatformExploreItem item;
  @override
  ConsumerState<PlatformCollectionPlayButton> createState() =>
      _CollectionPlayState();
}

class _CollectionPlayState extends ConsumerState<PlatformCollectionPlayButton> {
  bool _loading = false;
  Future<void> _play() async {
    if (_loading) return;
    final owner = ref.read(platformAccountProvider).value;
    final intent = ref.read(collectionPlayIntentProvider);
    final generation = intent.begin();
    var revoked = false;
    final subscription = ref.listenManual(platformAccountProvider, (
      previous,
      next,
    ) {
      if (previous?.value?.ownerId != next.value?.ownerId ||
          previous?.value?.token != next.value?.token) {
        revoked = true;
      }
    });
    bool current() =>
        mounted &&
        !revoked &&
        intent.owns(generation) &&
        ref.read(platformAccountProvider).value?.ownerId == owner?.ownerId &&
        ref.read(platformAccountProvider).value?.token == owner?.token;
    setState(() => _loading = true);
    try {
      final tracks = await completePublicCollection(ref, widget.item, current);
      if (mounted && current() && tracks.isNotEmpty) {
        await playBetaSelection(
          context,
          ref,
          tracks.first,
          playAll: tracks,
          stillCurrent: current,
        );
      }
    } catch (error) {
      if (mounted && current()) showPlatformFailure(context, error);
    } finally {
      subscription.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      brightness: Brightness.dark,
      colorScheme: Theme.of(context).colorScheme.copyWith(
        brightness: Brightness.dark,
        onSurface: Colors.white,
        onSurfaceVariant: Colors.white70,
      ),
    ),
    child: BetaGlassButton(
      key: ValueKey('cover-play-${widget.item.kind.name}-${widget.item.id}'),
      label: '播放${widget.item.title}全部歌曲',
      width: 48,
      height: 48,
      loading: _loading,
      onPressed: _loading ? null : () => unawaited(_play()),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: 27,
      ),
    ),
  );
}
