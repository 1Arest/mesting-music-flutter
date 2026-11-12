import '../../../shared/widgets/music_notice.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/automatic_song_paging.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_bottom_search.dart';
import '../../../shared/widgets/beta_page_search_layout.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';
import '../presentation/platform_design.dart';
import '../presentation/platform_feedback.dart';
import 'netease_connection_models.dart';
import 'netease_connections_controller.dart';
import 'netease_features_page.dart';
import 'netease_features_repository.dart';
import 'netease_user_page.dart';
import 'netease_user_providers.dart';
import 'netease_user_repository.dart';
import '../../themes/music_typography.dart';

/// Entry point from the My-page official counters. Pass the qualified owner ID
/// (`netease:<userId>`), never a token or an entire session in route arguments.
void openNeteasePersonalConnections(
  BuildContext context, {
  required String ownerId,
  bool initialFollowers = false,
}) => Navigator.of(context).push(
  mestingCupertinoRoute<void>(
    NeteasePersonalConnectionsPage(
      ownerId: ownerId,
      initialFollowers: initialFollowers,
    ),
  ),
);

class NeteasePersonalConnectionsPage extends ConsumerStatefulWidget {
  const NeteasePersonalConnectionsPage({
    required this.ownerId,
    this.initialFollowers = false,
    super.key,
  });
  final String ownerId;
  final bool initialFollowers;
  @override
  ConsumerState<NeteasePersonalConnectionsPage> createState() =>
      _NeteasePersonalConnectionsPageState();
}

class _NeteasePersonalConnectionsPageState
    extends ConsumerState<NeteasePersonalConnectionsPage> {
  late final NeteaseUserRepository _repository;
  late final PlatformSession? _identity;
  late final List<NeteaseConnectionsController> _tabs;
  late final BetaPageSearchController _search;
  final _scroll = [ScrollController(), ScrollController()];
  late bool _followers;
  bool _invalidated = false;
  int get _index => _followers ? 1 : 0;
  bool get _current =>
      mounted &&
      !_invalidated &&
      _identity?.platform == MusicPlatform.netease &&
      _identity?.ownerId == widget.ownerId &&
      ref.read(platformAccountProvider).value?.ownerId == widget.ownerId &&
      ref.read(platformAccountProvider).value?.token == _identity?.token &&
      identical(_repository, ref.read(neteaseUserRepositoryProvider));

  @override
  void initState() {
    super.initState();
    _followers = widget.initialFollowers;
    _repository = ref.read(neteaseUserRepositoryProvider);
    _identity = ref.read(platformAccountProvider).value;
    _tabs = [
      for (final followers in [false, true])
        NeteaseConnectionsController(
          repository: _repository,
          userId: _identity?.userId ?? '',
          followers: followers,
          isCurrent: () => _current,
        )..addListener(_changed),
    ];
    // The actual music bar owns the one editor. Each tab retains only its query
    // value, so changing tabs never creates a second field or a global search.
    _search = BetaPageSearchController(
      hintText: '搜索关注或粉丝',
      onChanged: _filterCurrentTab,
      onSubmitted: _filterCurrentTab,
      onCleared: () => _filterCurrentTab(''),
    );
    unawaited(Future<void>.microtask(() => _tabs[_index].start()));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _filterCurrentTab(String value) {
    if (_current) _tabs[_index].setQuery(value);
  }

  @override
  void dispose() {
    _search.dispose();
    for (final controller in [..._scroll, ..._tabs]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _select(bool value) {
    if (_followers == value || !_current) return;
    // Tapping a segment is not an instruction to restore the search keyboard.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _followers = value);
    final query = _tabs[_index].query;
    _search.text.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _search.hasResults = query.trim().isNotEmpty;
    if (query.trim().isNotEmpty) _search.setActive(true);
    unawaited(_tabs[_index].start());
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(neteaseUserRepositoryProvider);
    ref.listen(platformAccountProvider, (previous, next) {
      if (previous?.value?.ownerId != next.value?.ownerId ||
          previous?.value?.token != next.value?.token) {
        // Once a route's account changes it stays invalid, even if the same
        // owner logs back in before a previously pending response completes.
        _invalidated = true;
      }
    });
    ref.watch(platformAccountProvider);
    if (!_current) {
      return const PlatformPageFrame(
        title: '关注与粉丝',
        centerTitle: true,
        child: Center(child: Text('账号已变化，请返回后重新打开')),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final receivedSummary = ref.watch(neteasePersonalStatsProvider).value;
    final summary = receivedSummary?.ownerId == widget.ownerId
        ? receivedSummary
        : null;
    final frame = PlatformPageFrame(
      title: '关注与粉丝',
      centerTitle: true,
      actions: [
        CupertinoButton(
          key: const ValueKey('personal-connections-refresh'),
          padding: const EdgeInsets.all(10),
          onPressed: _tabs[_index].busy
              ? null
              : () {
                  ref.invalidate(neteasePersonalStatsProvider);
                  unawaited(_tabs[_index].refresh());
                },
          child: Icon(CupertinoIcons.arrow_clockwise, color: scheme.onSurface),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<bool>(
                groupValue: _followers,
                backgroundColor: scheme.surfaceContainerHighest,
                thumbColor: scheme.surface,
                children: {
                  false: _segment('关注', summary?.following, !_followers),
                  true: _segment('粉丝', summary?.followers, _followers),
                },
                onValueChanged: (value) {
                  if (value != null) _select(value);
                },
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                for (var index = 0; index < _tabs.length; index++)
                  TickerMode(
                    enabled: index == _index,
                    child: _tab(context, index),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return BetaPageSearchLayout(controller: _search, child: frame);
  }

  Widget _segment(String title, int? count, bool selected) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    child: Text(
      count == null ? title : '$title $count',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: MusicTypography.calloutSize,
        fontWeight: MusicTypography.bodyWeight,
      ),
    ),
  );

  Widget _tab(BuildContext context, int index) {
    final controller = _tabs[index];
    final scheme = Theme.of(context).colorScheme;
    final values = controller.visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 10, 4),
          child: Row(
            children: [
              if (index == 0)
                Expanded(
                  child:
                      CupertinoSlidingSegmentedControl<NeteaseConnectionFilter>(
                        key: const ValueKey('personal-connections-filter'),
                        groupValue: controller.filter,
                        backgroundColor: scheme.surfaceContainerHighest,
                        thumbColor: scheme.surface,
                        children: {
                          for (final value in NeteaseConnectionFilter.values)
                            value: Text(
                              switch (value) {
                                NeteaseConnectionFilter.all => '全部',
                                NeteaseConnectionFilter.artists => '歌手',
                                NeteaseConnectionFilter.users => '用户',
                              },
                              style: TextStyle(
                                fontSize: MusicTypography.footnoteSize,
                                color: scheme.onSurface,
                              ),
                            ),
                        },
                        onValueChanged: (value) {
                          if (value != null) {
                            _search.focus.unfocus();
                            controller.setFilter(value);
                          }
                        },
                      ),
                )
              else
                Expanded(
                  child: Text(
                    '关注我的人',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(width: 10),
              CupertinoButton(
                key: ValueKey('personal-connections-sort-$index'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                onPressed: () => _chooseSort(controller),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _sortLabel(controller.sort),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: MusicTypography.footnoteSize,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      CupertinoIcons.chevron_down,
                      size: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AutomaticSongPaging(
            enabled:
                !controller.complete &&
                !controller.busy &&
                controller.error == null,
            onLoadMore: controller.loadMore,
            child: CustomScrollView(
              key: PageStorageKey('personal-connections-list-$index'),
              controller: _scroll[index],
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                CupertinoSliverRefreshControl(onRefresh: controller.refresh),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      controller.complete
                          ? '${values.length} 个${controller.query.trim().isEmpty ? '条目' : '搜索结果'}'
                          : '已加载 ${controller.items.length} 个条目，${controller.busy ? '正在补齐完整列表' : '列表尚未完整'}',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: MusicTypography.captionSize,
                      ),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: values.length,
                  itemBuilder: (context, row) => _ConnectionRow(
                    key: ValueKey('connection-${values[row].key}'),
                    connection: values[row],
                  ),
                ),
                SliverPadding(
                  padding: BetaContentInsets.musicPaddingOf(
                    context,
                    const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _status(controller, values.isEmpty),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _status(NeteaseConnectionsController controller, bool empty) {
    if (!controller.started) return const SizedBox.shrink();
    if (controller.busy) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (controller.error != null) {
      return Column(
        children: [
          Text(controller.error!, textAlign: TextAlign.center),
          CupertinoButton(
            onPressed: controller.complete
                ? controller.refresh
                : controller.loadRemaining,
            child: const Text('重试'),
          ),
        ],
      );
    }
    if (!controller.complete) {
      return CupertinoButton(
        onPressed: controller.loadMore,
        child: const Text('继续加载'),
      );
    }
    return Center(
      child: Text(
        empty
            ? (controller.query.trim().isNotEmpty
                  ? '没有找到匹配的人'
                  : controller.filter == NeteaseConnectionFilter.artists
                  ? '还没有关注歌手'
                  : controller.followers
                  ? '还没有粉丝'
                  : '还没有关注的人')
            : '已显示全部',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  static String _sortLabel(NeteaseConnectionSort value) => switch (value) {
    NeteaseConnectionSort.official => '默认顺序',
    NeteaseConnectionSort.name => '昵称顺序',
    NeteaseConnectionSort.followTime => '关注时间',
  };

  Future<void> _chooseSort(NeteaseConnectionsController controller) async {
    final selected = await showCupertinoModalPopup<NeteaseConnectionSort>(
      context: context,
      requestFocus: false,
      builder: (context) => CupertinoActionSheet(
        title: const Text('列表排序', style: MusicTypography.titleEmphasis),
        message: Text(
          controller.canSortByTime
              ? '关注时间按最新在前排列'
              : '昵称排序随完整列表加载更新。网易云未提供完整关注时间时，保留默认顺序。',
        ),
        actions: [
          for (final value in NeteaseConnectionSort.values)
            CupertinoActionSheetAction(
              isDefaultAction: value == controller.sort,
              onPressed: () => Navigator.pop(context, value),
              child: Text(
                _sortLabel(value),
                style: MusicTypography.regularText,
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: MusicTypography.regularText),
        ),
      ),
    );
    if (!mounted || !_current || selected == null) return;
    if (!controller.setSort(selected)) {
      showMusicNotice(
        context,
        icon: Icons.info_outline_rounded,
        title: '网易云未提供完整关注时间，暂时无法按时间排序',
        message: '',
      );
    }
  }
}

class _ConnectionRow extends ConsumerWidget {
  const _ConnectionRow({required this.connection, super.key});
  final NeteaseConnection connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                if (connection.user != null) {
                  openNeteaseUser(context, connection.user!);
                } else {
                  openNeteaseItem(
                    context,
                    NeteaseItem(
                      id: connection.id,
                      name: connection.name,
                      kind: NeteaseEntity.artist,
                      cover: connection.avatar,
                    ),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    ClipOval(
                      child: connection.avatar.isEmpty
                          ? SizedBox.square(
                              dimension: 54,
                              child: ColoredBox(
                                color: scheme.surfaceContainerHighest,
                                child: Icon(
                                  connection.kind ==
                                          NeteaseConnectionKind.artist
                                      ? CupertinoIcons.music_mic
                                      : CupertinoIcons.person,
                                ),
                              ),
                            )
                          : ArtworkImage(
                              uri: connection.avatar,
                              width: 54,
                              height: 54,
                            ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            connection.name.isEmpty ? '网易云用户' : connection.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: MusicTypography.calloutSize,
                              fontWeight: MusicTypography.bodyWeight,
                            ),
                          ),
                          if (connection.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              connection.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: MusicTypography.captionSize,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (connection.user != null)
            NeteaseFollowButton(user: connection.user!, cupertino: true)
          else
            _ArtistRelationButton(connection: connection),
        ],
      ),
    );
  }
}

class _ArtistRelationButton extends ConsumerWidget {
  const _ArtistRelationButton({required this.connection});
  final NeteaseConnection connection;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(neteaseArtistRelationsProvider)[connection.id];
    final subscribed = state?.followed ?? true;
    final scheme = Theme.of(context).colorScheme;
    return CupertinoButton(
      key: ValueKey('netease-artist-follow-${connection.id}'),
      minimumSize: const Size(84, 38),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      borderRadius: BorderRadius.circular(22),
      color: subscribed ? scheme.surfaceContainerHighest : scheme.primary,
      disabledColor: scheme.surfaceContainerHighest,
      onPressed: state?.busy == true
          ? null
          : () async {
              final identity = ref.read(platformAccountProvider).value;
              if (subscribed) {
                final confirmed = await showCupertinoDialog<bool>(
                  context: context,
                  builder: (context) => CupertinoAlertDialog(
                    title: const Text(
                      '取消关注歌手？',
                      style: MusicTypography.titleEmphasis,
                    ),
                    content: Text('将不再关注${connection.name}。'),
                    actions: [
                      CupertinoDialogAction(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text(
                          '保留关注',
                          style: MusicTypography.regularText,
                        ),
                      ),
                      CupertinoDialogAction(
                        isDestructiveAction: true,
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text(
                          '取消关注',
                          style: MusicTypography.regularText,
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
              }
              bool current() =>
                  context.mounted &&
                  ref.read(platformAccountProvider).value?.ownerId ==
                      identity?.ownerId &&
                  ref.read(platformAccountProvider).value?.token ==
                      identity?.token;
              if (!current()) return;
              try {
                await ref
                    .read(neteaseArtistRelationsProvider.notifier)
                    .setSubscribed(
                      connection.id,
                      !subscribed,
                      previous: subscribed,
                    );
              } catch (error) {
                if (context.mounted && current()) {
                  showPlatformFailure(context, error);
                }
              }
            },
      child: state?.busy == true
          ? const CupertinoActivityIndicator(radius: 9)
          : Text(
              subscribed ? '已关注' : '关注',
              style: TextStyle(
                fontSize: MusicTypography.footnoteSize,
                fontWeight: MusicTypography.bodyWeight,
                color: subscribed ? scheme.onSurface : scheme.onPrimary,
              ),
            ),
    );
  }
}
