import '../qishui/qishui_song_actions.dart';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../core/platform/share_bridge.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../library/favorite_pins_provider.dart';
import '../../library/library_providers.dart';
import '../../library/presentation/library_access.dart';
import '../../downloads/audio_downloads_page.dart';
import '../../playlists/presentation/add_to_playlist_sheet.dart';
import '../data/platform_category_search.dart';
import '../data/song_menu_details.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';
import '../platform_backend_providers.dart';
import '../netease/fallback/netease_source_picker.dart';
import 'platform_catalog_detail_page.dart';
import 'platform_comments_page.dart';
import 'platform_feedback.dart';
import '../../themes/music_typography.dart';

class SongMenuExtraAction {
  const SongMenuExtraAction(
    this.label,
    this.icon,
    this.perform, {
    this.destructive = false,
  });
  final String label;
  final IconData icon;
  final Future<void> Function() perform;
  final bool destructive;
}

class SongActionsButton extends ConsumerWidget {
  const SongActionsButton({
    required this.track,
    this.favorites = false,
    this.enabled = true,
    this.playable = true,
    this.extras = const [],
    super.key,
  });
  final Track track;
  final bool favorites, enabled, playable;
  final List<SongMenuExtraAction> extras;
  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    key: ValueKey('song-actions-${track.id}'),
    tooltip: '歌曲操作',
    onPressed: enabled
        ? () => showSongActions(
            context,
            ref,
            track,
            favorites: favorites,
            playable: playable,
            extras: extras,
          )
        : null,
    icon: const Icon(Icons.more_vert_rounded, size: 23),
  );
}

/// Return an intent from the sheet and perform it through the original audio,
/// library and download owners. Never keep a row WidgetRef alive in a new route.
Future<void> showSongActions(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  bool favorites = false,
  bool playable = true,
  List<SongMenuExtraAction> extras = const [],
  Future<Track> Function()? prepareForQueue,
}) async {
  if (track.source == TrackSource.qishui) {
    return showQishuiSongActions(
      context,
      ref,
      track,
      extras: extras.map((e) => (e.label, e.icon, e.perform)).toList(),
    );
  }
  final account = ref.read(platformAccountProvider).value;
  final owner = ref.read(activeLibraryOwnerProvider);
  final library = ref.read(libraryRepositoryProvider);
  bool current() =>
      context.mounted &&
      ref.read(activeLibraryOwnerProvider) == owner &&
      identical(ref.read(libraryRepositoryProvider), library) &&
      identical(ref.read(platformAccountProvider).value, account);
  final matching =
      account == null ||
      track.source == TrackSource.local ||
      track.source.name == account.platform.name;
  final remote =
      track.source == TrackSource.netease || track.source == TrackSource.kugou;
  final api = ref.read(musicPlatformApiProvider);
  final music = track.source == TrackSource.netease && matching
      ? ref.read(neteaseMusicRepositoryProvider)
      : null;
  final repository = SongMenuDetailsRepository(
    netease: (path, query) {
      if (!current() || music == null) throw StateError('账号已变化，请重新打开菜单');
      return music.call(path, query);
    },
    kugou: (path, query) {
      if (!current()) throw StateError('账号已变化，请重新打开菜单');
      return api.get(
        path,
        query: query.map((k, v) => MapEntry(k, '$v')),
        expectedSession: account?.platform == MusicPlatform.kugou
            ? account
            : null,
      );
    },
  );
  ModalRoute<dynamic>? sheetRoute;
  final choice = await showLiquidGlassBottomSheet<Object>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheet) {
      sheetRoute = ModalRoute.of(sheet);
      return SongActionsPanel(
        track: track,
        favorites: favorites,
        playable: playable,
        libraryAvailable:
            account == null || track.source.name == account.platform.name,
        platformAvailable: remote && matching,
        extras: extras,
        loadDetails: remote && matching ? () => repository.load(track) : null,
        reloadDetails: remote && matching
            ? (previous, part) =>
                  repository.load(track, previous: previous, only: part)
            : null,
        onSelect: (value) => Navigator.pop(sheet, value),
      );
    },
  );
  // ModalRoute.popped resolves when pop starts. Waiting for completed avoids a
  // second sheet/page competing with the outgoing glass layer's reverse path.
  await sheetRoute?.completed;
  if (choice == null || !context.mounted) return;
  if (!current()) {
    showPlatformFailure(context, StateError('账号已变化，请重新打开歌曲菜单'));
    return;
  }
  try {
    if (choice is SongMenuExtraAction) {
      await choice.perform();
      return;
    }
    if (choice is _SongInfoIntent) {
      await _openSongInfo(context, track, choice, current);
      return;
    }
    switch (choice) {
      case 'next':
        final prepared = prepareForQueue == null
            ? track
            : await prepareForQueue();
        if (!current()) return;
        final moved = await ref
            .read(audioHandlerProvider)
            .playNextInQueue(prepared);
        if (context.mounted && current()) {
          showMusicNotice(
            context,
            icon: CupertinoIcons.text_badge_plus,
            title: moved ? '已设为下一首播放' : '这首歌正在播放',
            message: '',
          );
        }
      case 'pin':
        if (!ref.read(favoriteTrackIdsProvider).contains(track.id)) {
          throw StateError('歌曲已不在当前账号的喜欢列表中');
        }
        final pins = ref.read(favoritePinsProvider);
        final pinned = pins.contains(owner, track.id);
        await pins.toggle(owner, track);
        if (context.mounted && current()) {
          showMusicNotice(
            context,
            icon: CupertinoIcons.pin,
            title: pinned ? '已取消置顶' : '已置顶',
            message: '',
          );
        }
      case 'favorite':
        if (await ensureLibraryAccess(
              context,
              ref,
              reason: '登录后管理喜欢的歌曲',
              redirect: '/music',
            ) &&
            context.mounted &&
            current()) {
          final was = ref.read(favoriteTrackIdsProvider).contains(track.id);
          await library.toggleFavorite(track);
          if (context.mounted && current()) {
            showMusicNotice(
              context,
              icon: CupertinoIcons.heart,
              title: was ? '已取消喜欢' : '已添加到喜欢',
              message: '',
            );
          }
        }
      case 'playlist':
        await showAddToPlaylistSheet(context, ref, track);
      case 'download':
        await enqueueAudioDownload(context, ref, track);
      case 'comments':
        if (await ensureLibraryAccess(
              context,
              ref,
              reason: '登录对应音乐平台查看评论',
              redirect: '/music',
            ) &&
            context.mounted &&
            current()) {
          await openPlatformSongComments(context, ref, track);
        }
      case 'share':
        // Share only public catalogue information. Device-private audio paths,
        // headers and account state must never leave through Android sharing.
        final url = Uri.tryParse(track.externalUrl);
        final public = url != null && {'http', 'https'}.contains(url.scheme)
            ? track.externalUrl
            : '';
        await ShareBridge.shareText(
          [
            '${track.title} — ${track.artist}',
            if (public.isNotEmpty) public,
          ].join('\n'),
          title: track.title,
        );
      case 'source':
        await showNeteaseTrackSources(context, ref, track);
    }
  } catch (error) {
    if (context.mounted) showPlatformFailure(context, error);
  }
}

/// Kept independently injectable for host render/interaction tests. Metadata
/// failure leaves the real song operations usable and exposes a local retry.
class SongActionsPanel extends ConsumerStatefulWidget {
  const SongActionsPanel({
    required this.track,
    required this.onSelect,
    this.favorites = false,
    this.playable = true,
    this.libraryAvailable = true,
    this.platformAvailable = true,
    this.extras = const [],
    this.loadDetails,
    this.reloadDetails,
    super.key,
  });
  final Track track;
  final ValueChanged<Object> onSelect;
  final bool favorites, playable, libraryAvailable, platformAvailable;
  final List<SongMenuExtraAction> extras;
  final Future<SongMenuDetails> Function()? loadDetails;
  final Future<SongMenuDetails> Function(SongMenuDetails, SongDetailsSection)?
  reloadDetails;
  @override
  ConsumerState<SongActionsPanel> createState() => _SongActionsPanelState();
}

class _SongActionsPanelState extends ConsumerState<SongActionsPanel> {
  late Future<SongMenuDetails> _details = _load();
  Future<SongMenuDetails> _load() =>
      widget.loadDetails?.call() ??
      Future.value(SongMenuDetails.local(widget.track));
  void _retry(SongMenuDetails data, SongDetailsSection section) => setState(() {
    // FutureBuilder 保留上一个已取得的值，只更新失败部分的结果。
    _details = widget.reloadDetails?.call(data, section) ?? _load();
  });
  Widget _action(String label, IconData icon, Object intent, {Color? color}) =>
      ListTile(
        key: intent is String ? ValueKey('song-menu-$intent') : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 3),
        minVerticalPadding: 12,
        leading: Icon(icon, size: 25, color: color),
        title: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: MusicTypography.calloutSize, color: color),
        ),
        onTap: () => widget.onSelect(intent),
      );
  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final owner = ref.watch(activeLibraryOwnerProvider);
    final pins = ref.watch(favoritePinsProvider);
    final favorite = ref.watch(favoriteTrackIdsProvider).contains(track.id);
    final netease = track.source == TrackSource.netease;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: ValueKey('song-actions-panel-${track.source.name}'),
      height: MediaQuery.sizeOf(context).height * .78,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 8, 16),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(netease ? 6 : 10),
                      child: TrackArtwork(track: track, width: 50, height: 50),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '歌曲：${track.title}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: MusicTypography.bodySize,
                              fontWeight: MusicTypography.titleWeight,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: MusicTypography.footnoteSize,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭歌曲菜单',
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(CupertinoIcons.xmark, size: 19),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  children: [
                    if (widget.favorites && favorite)
                      _action(
                        pins.contains(owner, track.id) ? '取消置顶' : '置顶',
                        CupertinoIcons.pin,
                        'pin',
                      ),
                    if (widget.playable)
                      _action('下一首播放', CupertinoIcons.text_badge_plus, 'next'),
                    if (widget.libraryAvailable) ...[
                      _action(
                        favorite ? '取消喜欢' : '喜欢',
                        favorite
                            ? CupertinoIcons.heart_fill
                            : CupertinoIcons.heart,
                        'favorite',
                        color: favorite ? scheme.primary : null,
                      ),
                      _action(
                        netease ? '收藏到歌单' : '加入歌单',
                        CupertinoIcons.add_circled,
                        'playlist',
                      ),
                    ],
                    if (track.isRemote)
                      _action(
                        '下载',
                        CupertinoIcons.arrow_down_circle,
                        'download',
                      ),
                    if (widget.platformAvailable)
                      _action('评论', CupertinoIcons.text_bubble, 'comments'),
                    _action('分享', CupertinoIcons.share, 'share'),
                    FutureBuilder<SongMenuDetails>(
                      future: _details,
                      builder: (context, result) {
                        final data =
                            result.data ?? SongMenuDetails.local(track);
                        return Column(
                          children: [
                            const Divider(
                              height: 16,
                              indent: 22,
                              endIndent: 22,
                            ),
                            if (data.artists.isNotEmpty)
                              _action(
                                '歌手：${data.artists.map((p) => p.name).join(' / ')}',
                                CupertinoIcons.person,
                                _SongInfoIntent('artist', data),
                              ),
                            _action(
                              '创作者${data.creators.isEmpty ? '' : '：${data.creators.map((p) => p.name).join(' / ')}'}',
                              CupertinoIcons.person_2,
                              _SongInfoIntent('creators', data),
                            ),
                            if (data.album.isNotEmpty)
                              _action(
                                '专辑：${data.album}',
                                CupertinoIcons.square_stack,
                                _SongInfoIntent('album', data),
                              ),
                            if (result.connectionState != ConnectionState.done)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: BetaActivityIndicator(),
                              ),
                            if (result.hasError)
                              TextButton.icon(
                                onPressed: () => setState(() {
                                  _details = _load();
                                }),
                                icon: const Icon(
                                  CupertinoIcons.arrow_clockwise,
                                ),
                                label: const Text('歌手、专辑资料读取失败，重试'),
                              ),
                            for (final section in data.failed)
                              TextButton.icon(
                                onPressed:
                                    result.connectionState ==
                                        ConnectionState.done
                                    ? () => _retry(data, section)
                                    : null,
                                icon: const Icon(
                                  CupertinoIcons.arrow_clockwise,
                                ),
                                label: Text('${section.label}读取失败，重试'),
                              ),
                            if (!result.hasError &&
                                result.connectionState ==
                                    ConnectionState.done &&
                                data.creators.isEmpty &&
                                !data.failed.contains(
                                  SongDetailsSection.creators,
                                ) &&
                                widget.loadDetails != null)
                              TextButton(
                                onPressed: () => setState(() {
                                  _details = _load();
                                }),
                                child: const Text('重新读取歌曲资料'),
                              ),
                          ],
                        );
                      },
                    ),
                    if (track.source == TrackSource.netease &&
                        !track.hasLocalAudio &&
                        widget.platformAvailable)
                      _action(
                        '选择音乐来源',
                        CupertinoIcons.antenna_radiowaves_left_right,
                        'source',
                      ),
                    for (final extra in widget.extras)
                      _action(
                        extra.label,
                        extra.icon,
                        extra,
                        color: extra.destructive ? scheme.error : null,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SongInfoIntent {
  const _SongInfoIntent(this.kind, this.details);
  final String kind;
  final SongMenuDetails details;
}

Future<void> _openSongInfo(
  BuildContext context,
  Track track,
  _SongInfoIntent intent,
  bool Function() current,
) async {
  final details = intent.details;
  Future<void> open(PlatformSearchKind kind, String id, String title) async {
    if (!context.mounted || !current()) return;
    await Navigator.of(context, rootNavigator: true).push(
      MestingPageRoute<void>(
        builder: (_) => PlatformCatalogDetailPage(
          hit: PlatformSearchHit(
            kind: kind,
            id: id,
            title: title,
            cover: details.cover,
          ),
        ),
      ),
    );
  }

  if (intent.kind == 'album' && details.albumId.isNotEmpty) {
    await open(PlatformSearchKind.albums, details.albumId, details.album);
    return;
  }
  if (intent.kind == 'artist' &&
      details.artists.length == 1 &&
      details.artists.first.id.isNotEmpty) {
    await open(
      PlatformSearchKind.artists,
      details.artists.first.id,
      details.artists.first.name,
    );
    return;
  }
  ModalRoute<dynamic>? infoRoute;
  final selected = await showLiquidGlassBottomSheet<SongMenuPerson>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheet) {
      infoRoute = ModalRoute.of(sheet);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * .65,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                intent.kind == 'creators'
                    ? '创作者'
                    : intent.kind == 'artist'
                    ? '歌手'
                    : '专辑',
                style: const TextStyle(
                  fontSize: MusicTypography.sectionTitleSize,
                  fontWeight: MusicTypography.titleWeight,
                ),
              ),
              const SizedBox(height: 16),
              if (intent.kind == 'album') Text(details.album),
              if (intent.kind == 'creators' && details.creators.isEmpty)
                const Text('当前歌曲资料未提供可核实的创作者信息。'),
              for (final person
                  in intent.kind == 'creators'
                      ? details.creators
                      : intent.kind == 'artist'
                      ? details.artists
                      : const <SongMenuPerson>[])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(person.name),
                  subtitle: person.role.isEmpty ? null : Text(person.role),
                  trailing: intent.kind == 'artist' && person.id.isNotEmpty
                      ? const Icon(CupertinoIcons.chevron_right, size: 18)
                      : null,
                  onTap: intent.kind == 'artist' && person.id.isNotEmpty
                      ? () => Navigator.pop(sheet, person)
                      : null,
                ),
            ],
          ),
        ),
      );
    },
  );
  await infoRoute?.completed;
  if (selected != null && context.mounted) {
    await open(PlatformSearchKind.artists, selected.id, selected.name);
  }
}
