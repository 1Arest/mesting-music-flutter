import 'dart:async';
import '../../../shared/widgets/collection_play_all_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/platform/share_bridge.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_glass_action.dart';
import '../../../shared/widgets/beta_root_tab_viewport.dart';
import '../../downloads/audio_downloads_page.dart';
import '../../library/library_providers.dart';
import '../../player/presentation/beta_playback_actions.dart';
import '../data/music_platform_api.dart';
import '../data/platform_explore.dart';
import '../data/platform_library_repository.dart';
import '../data/platform_public_playlist.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';
import '../platform_backend_providers.dart';
import 'platform_collection_play.dart';
import 'platform_comments_page.dart';
import 'platform_feedback.dart';
import 'platform_ranking_header.dart';
import '../../themes/music_typography.dart';

/// Public discovery/search playlists share the chart presentation, while their
/// business operations keep the real playlist identity. Personal cloud pages
/// remain independent and retain all existing management controls.
class PlatformPublicPlaylistHeader extends ConsumerStatefulWidget {
  const PlatformPublicPlaylistHeader({
    required this.item,
    required this.tracks,
    this.total,
    super.key,
  });
  final PlatformExploreItem item;
  final List<Track> tracks;
  final int? total;
  @override
  ConsumerState<PlatformPublicPlaylistHeader> createState() =>
      _PublicHeaderState();
}

class _PublicHeaderState extends ConsumerState<PlatformPublicPlaylistHeader> {
  PlatformCoverPlayLease? _playLease;
  late final _owner = ref.read(platformAccountProvider).value;
  PublicPlaylistInfo? _info;
  bool _revoked = false, _reading = false, _busy = false, _playing = false;
  bool? _subscribed;
  String? _error;
  bool get _netease => _owner?.platform == MusicPlatform.netease;
  bool get _current =>
      mounted &&
      !_revoked &&
      _owner != null &&
      ref.read(platformAccountProvider).value?.ownerId == _owner.ownerId &&
      ref.read(platformAccountProvider).value?.token == _owner.token;
  bool get _mine => _info?.creatorId == _owner?.userId;
  @override
  void initState() {
    super.initState();
    unawaited(Future<void>.microtask(_read));
  }

  Future<void> _read() async {
    if (!_current || _reading) return;
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final info = await PublicPlaylistRepository(
        api: ref.read(musicPlatformApiProvider),
        owner: _owner!,
        isCurrent: () => _current,
        netease: _netease ? ref.read(neteaseMusicRepositoryProvider) : null,
      ).info(widget.item);
      if (!_current) return;
      var subscribed = info.subscribed;
      final library = ref.read(libraryRepositoryProvider);
      if (!_netease && library is PlatformLibraryRepository) {
        subscribed = await library.publicSubscription(widget.item.id) != null;
      }
      if (_current) {
        setState(() {
          _info = info;
          _subscribed = subscribed;
        });
      }
    } catch (_) {
      if (_current) setState(() => _error = '歌单资料读取失败，点击重试');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _save() async {
    if (!_current || _busy || _mine) return;
    if (_info == null || _subscribed == null) return _read();
    final value = !_subscribed!;
    setState(() => _busy = true);
    try {
      if (_netease) {
        await ref.read(neteaseMusicRepositoryProvider).call(
          '/playlist/subscribe',
          {'id': widget.item.id, 'subscribe': value},
        );
      } else {
        final library = ref.read(libraryRepositoryProvider);
        if (library is! PlatformLibraryRepository) {
          throw const MusicPlatformException('当前歌单收藏不可用');
        }
        await library.subscribePublicPlaylist(
          globalId: widget.item.id,
          name: widget.item.title,
          creatorId: _info!.creatorId,
          creatorListId: _info!.creatorListId,
          subscribe: value,
        );
      }
      if (!mounted || !_current) return;
      setState(() => _subscribed = null);
      await _read();
    } catch (error) {
      if (mounted && _current) {
        setState(() => _subscribed = null);
        showPlatformFailure(context, error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _play({bool download = false}) async {
    if (!_current || _busy) return;
    final lease = download
        ? null
        : PlatformCoverPlayLease(ref, context, () => mounted);
    if (lease != null) _playLease = lease;
    bool current() => _current && (lease?.current ?? true);
    setState(() {
      _busy = true;
      _playing = !download;
    });
    try {
      final tracks = await completePublicCollection(ref, widget.item, current);
      if (!mounted) return;
      if (!current() || tracks.isEmpty) return;
      if (download) {
        await enqueueAudioDownloads(context, ref, tracks);
      } else {
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
      lease?.dispose();
      if (identical(_playLease, lease)) _playLease = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _playing = false;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playLease?.observePageVisibility();
    if (!BetaTabVisibility.of(context)) {
      _playLease?.revoke();
    }
  }

  @override
  void dispose() {
    _playLease?.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final link = _netease
        ? Uri.https('music.163.com', '/playlist', {'id': widget.item.id})
        : Uri.https('www.kugou.com', '/songlist/gcid_${widget.item.id}/');
    try {
      await ShareBridge.shareText(
        '${widget.item.title}\n$link',
        title: widget.item.title,
      );
    } catch (error) {
      if (mounted && _current) showPlatformFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(platformAccountProvider);
    ref.listen(platformAccountProvider, (previous, next) {
      if (previous?.value?.ownerId != next.value?.ownerId ||
          previous?.value?.token != next.value?.token) {
        _revoked = true;
      }
    });
    if (!_current) return const SizedBox.shrink();
    final count = _info?.total ?? widget.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlatformCollectionMasthead(
          title: widget.item.title,
          platform: _owner!.platform,
          cover:
              [
                    _info?.cover,
                    widget.item.cover,
                    widget.tracks.firstOrNull?.coverAsset,
                  ]
                  .whereType<String>()
                  .where((cover) => cover.isNotEmpty)
                  .firstOrNull ??
              '',
          period: '',
          secondary: [
            if (_info?.creator.isNotEmpty == true) _info!.creator,
            if (count != null) '$count 首歌曲',
          ].join(' · '),
          coverOnly: true,
          actions: [
            PlatformCollectionAction(
              id: 'save',
              label: _mine
                  ? '我的歌单'
                  : _subscribed == true
                  ? '已收藏'
                  : '收藏',
              icon: _subscribed == true
                  ? Icons.library_add_check_outlined
                  : Icons.library_add_outlined,
              count: _info?.collections,
              onPressed: _busy || _mine ? null : () => unawaited(_save()),
            ),
            PlatformCollectionAction(
              id: 'comments',
              label: '评论',
              icon: Icons.chat_bubble_outline,
              count: _info?.comments,
              onPressed: _busy
                  ? null
                  : () => openPlatformPlaylistComments(
                      context,
                      ref,
                      id: widget.item.id,
                      name: widget.item.title,
                    ),
            ),
            PlatformCollectionAction(
              id: 'share',
              label: '分享',
              icon: Icons.share_outlined,
              count: _info?.shares,
              onPressed: _busy ? null : () => unawaited(_share()),
            ),
          ],
        ),
        if (_error != null)
          TextButton(onPressed: _reading ? null : _read, child: Text(_error!)),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  key: const ValueKey('playlist-play-all'),
                  onPressed: _busy || widget.tracks.isEmpty ? null : _play,
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Row(
                    children: [
                      CollectionPlayGlyph(loading: _playing),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          _playing
                              ? '读取完整歌单'
                              : '播放全部${count == null ? '' : '（$count）'}',
                          style: TextStyle(
                            fontSize: MusicTypography.bodySize,
                            fontWeight: MusicTypography.titleWeight,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              BetaGlassAction(
                label: '下载完整歌单',
                icon: Icons.download_outlined,
                blue: false,
                loading: _busy && !_playing,
                onPressed: _busy || widget.tracks.isEmpty
                    ? null
                    : () => unawaited(_play(download: true)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
