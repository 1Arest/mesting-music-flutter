import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/artwork_reveal_boundary.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../domain/platform_search_user.dart';
import '../music_platform_providers.dart';
import '../presentation/platform_design.dart';
import '../presentation/platform_feedback.dart';
import 'netease_features_page.dart';
import 'netease_features_repository.dart';
import 'netease_user_providers.dart';
import 'netease_user_repository.dart';
import '../../themes/music_typography.dart';

void openNeteaseUser(BuildContext context, PlatformSearchUser user) =>
    Navigator.of(context).push(
      MestingPageRoute<void>(
        builder: (_) => NeteaseUserProfilePage(user: user),
      ),
    );

/// Relationship controls are shared across search, profiles and connection
/// lists. Glass press/drag cancellation remains in the common implementation.
class NeteaseFollowButton extends ConsumerWidget {
  const NeteaseFollowButton({
    required this.user,
    this.cupertino = false,
    super.key,
  });
  final PlatformSearchUser user;
  final bool cupertino;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(platformAccountProvider).value?.userId == user.id) {
      return const Text('我自己');
    }
    final relation = ref.watch(neteaseUserRelationsProvider)[user.id];
    final followed = relation?.followed ?? user.followed;
    final label = followed ? (user.followsMe ? '互相关注' : '已关注') : '关注';
    Future<void> toggle() async {
      final identity = ref.read(platformAccountProvider).value;
      if (followed) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => cupertino
              ? CupertinoAlertDialog(
                  title: const Text(
                    '取消关注？',
                    style: MusicTypography.titleEmphasis,
                  ),
                  content: Text('将不再关注${user.nickname}。'),
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
                )
              : AlertDialog(
                  title: const Text('取消关注？'),
                  content: Text('将不再关注${user.nickname}。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('保留关注'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('取消关注'),
                    ),
                  ],
                ),
        );
        if (confirmed != true || !context.mounted) return;
      }
      if (!context.mounted ||
          ref.read(platformAccountProvider).value?.ownerId !=
              identity?.ownerId ||
          ref.read(platformAccountProvider).value?.token != identity?.token) {
        return;
      }
      try {
        await ref
            .read(neteaseUserRelationsProvider.notifier)
            .setFollowed(user.id, !followed, previous: followed);
      } catch (error) {
        if (context.mounted &&
            ref.read(platformAccountProvider).value?.ownerId ==
                identity?.ownerId &&
            ref.read(platformAccountProvider).value?.token == identity?.token) {
          showPlatformFailure(context, error);
        }
      }
    }

    if (cupertino) {
      final colors = Theme.of(context).colorScheme;
      return Semantics(
        label: '$label ${user.nickname}',
        button: true,
        child: CupertinoButton(
          key: ValueKey('netease-follow-${user.id}'),
          onPressed: relation?.busy == true ? null : toggle,
          minimumSize: const Size(84, 38),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          borderRadius: BorderRadius.circular(22),
          color: followed ? colors.surfaceContainerHighest : colors.primary,
          disabledColor: colors.surfaceContainerHighest,
          child: relation?.busy == true
              ? const CupertinoActivityIndicator(radius: 9)
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: MusicTypography.footnoteSize,
                    fontWeight: MusicTypography.bodyWeight,
                    color: followed ? colors.onSurface : colors.onPrimary,
                  ),
                ),
        ),
      );
    }
    return BetaGlassButton(
      key: ValueKey('netease-follow-${user.id}'),
      label: '$label ${user.nickname}',
      height: 48,
      horizontalPadding: 14,
      fontSize: 13,
      accent: !followed,
      loading: relation?.busy == true,
      onPressed: toggle,
      child: Text(label),
    );
  }
}

class NeteaseSearchUserRow extends StatelessWidget {
  const NeteaseSearchUserRow({required this.user, super.key});
  final PlatformSearchUser user;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => openNeteaseUser(context, user),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  _Avatar(user: user, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.nickname,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: MusicTypography.calloutSize,
                            fontWeight: MusicTypography.bodyWeight,
                          ),
                        ),
                        if (user.signature.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            user.signature,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: MusicTypography.footnoteSize,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
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
        const SizedBox(width: 10),
        NeteaseFollowButton(user: user),
      ],
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.size});
  final PlatformSearchUser user;
  final double size;
  @override
  Widget build(BuildContext context) => ClipOval(
    child: user.avatar.isEmpty
        ? SizedBox.square(
            dimension: size,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.person_outline),
            ),
          )
        : ArtworkImage(uri: user.avatar, width: size, height: size),
  );
}

class NeteaseUserProfilePage extends ConsumerStatefulWidget {
  const NeteaseUserProfilePage({required this.user, super.key});
  final PlatformSearchUser user;
  @override
  ConsumerState<NeteaseUserProfilePage> createState() =>
      _NeteaseUserProfilePageState();
}

class _NeteaseUserProfilePageState
    extends ConsumerState<NeteaseUserProfilePage> {
  late final repository = ref.read(neteaseUserRepositoryProvider);
  late PlatformSearchUser user = widget.user;
  final _playlists = <NeteasePublicPlaylist>[];
  bool _busy = false, _more = true;
  int _offset = 0;
  String? _profileError, _playlistError;
  bool get current =>
      mounted && identical(repository, ref.read(neteaseUserRepositoryProvider));

  @override
  void initState() {
    super.initState();
    unawaited(Future<void>.microtask(_profile));
    unawaited(Future<void>.microtask(_loadMore));
  }

  Future<void> _profile() async {
    try {
      final value = await repository.profile(widget.user.id);
      if (current) {
        setState(() {
          user = value;
          _profileError = null;
        });
      }
    } catch (_) {
      if (current) setState(() => _profileError = '资料暂时无法更新');
    }
  }

  Future<void> _loadMore() async {
    if (_busy || !_more || !current) return;
    setState(() {
      _busy = true;
      _playlistError = null;
    });
    try {
      final page = await repository.playlists(widget.user.id, _offset);
      if (!current) return;
      setState(() {
        final ids = _playlists.map((v) => v.id).toSet();
        _playlists.addAll(page.items.where((v) => ids.add(v.id)));
        _offset += page.consumed;
        _more = page.more;
      });
    } catch (_) {
      if (current) setState(() => _playlistError = '歌单暂时无法加载，点此重试');
    } finally {
      if (current) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(neteaseUserRepositoryProvider);
    if (!current) {
      return const PlatformPageFrame(
        title: '用户主页',
        child: Center(child: Text('账号已变化，请返回后重新打开')),
      );
    }
    final relation = ref.watch(neteaseUserRelationsProvider)[user.id];
    final followers =
        user.followers +
        (relation == null
            ? 0
            : (relation.followed ? 1 : 0) - (user.followed ? 1 : 0));
    final created = _playlists.where((v) => v.creator == user.id).toList();
    final collected = _playlists.where((v) => v.creator != user.id).toList();
    return PlatformPageFrame(
      title: '用户主页',
      child: ListView(
        padding: BetaContentInsets.musicPaddingOf(
          context,
          EdgeInsets.fromLTRB(20, 18, 20, 180),
        ),
        children: [
          Row(
            children: [
              _Avatar(user: user, size: 80),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.nickname,
                      style: const TextStyle(
                        fontSize: MusicTypography.sectionTitleSize,
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('网易云用户 · ${user.id}'),
                    if (user.level != null) Text('Lv.${user.level}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 18,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              NeteaseFollowButton(user: user),
              TextButton(
                onPressed: () => _connections(false),
                child: Text('${user.following} 关注'),
              ),
              TextButton(
                onPressed: () => _connections(true),
                child: Text('${followers.clamp(0, 1 << 40)} 粉丝'),
              ),
            ],
          ),
          if (user.signature.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(user.signature),
          ],
          if (user.description.isNotEmpty && user.description != user.signature)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(user.description),
            ),
          if (_profileError != null)
            TextButton(onPressed: _profile, child: Text('$_profileError，重试')),
          const SizedBox(height: 24),
          _playlistSection('创建的歌单', created),
          _playlistSection('收藏的歌单', collected),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(20),
              child: ArtworkPendingContent(
                child: Center(child: BetaActivityIndicator()),
              ),
            ),
          if (_playlistError != null)
            TextButton(onPressed: _loadMore, child: Text(_playlistError!))
          else if (_more && !_busy)
            Center(
              child: BetaGlassButton(
                onPressed: _loadMore,
                child: const Text('加载更多歌单'),
              ),
            )
          else if (!_busy && _playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('暂无可查看的公开歌单'),
            ),
        ],
      ),
    );
  }

  void _connections(bool followers) => Navigator.of(context).push(
    MestingPageRoute<void>(
      builder: (_) =>
          NeteaseUserConnectionsPage(user: user, followers: followers),
    ),
  );

  Widget _playlistSection(String title, List<NeteasePublicPlaylist> values) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: MusicTypography.headingSize,
                fontWeight: MusicTypography.titleWeight,
              ),
            ),
          ),
          for (final value in values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ArtworkImage(uri: value.cover, width: 52, height: 52),
              ),
              title: Text(
                value.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${value.trackCount} 首'),
              onTap: () => openNeteaseItem(
                context,
                NeteaseItem(
                  id: value.id,
                  name: value.name,
                  kind: NeteaseEntity.playlist,
                  cover: value.cover,
                ),
              ),
            ),
        ],
      );
}

class NeteaseUserConnectionsPage extends ConsumerStatefulWidget {
  const NeteaseUserConnectionsPage({
    required this.user,
    required this.followers,
    super.key,
  });
  final PlatformSearchUser user;
  final bool followers;
  @override
  ConsumerState<NeteaseUserConnectionsPage> createState() =>
      _NeteaseUserConnectionsPageState();
}

class _NeteaseUserConnectionsPageState
    extends ConsumerState<NeteaseUserConnectionsPage> {
  late final repository = ref.read(neteaseUserRepositoryProvider);
  final _users = <PlatformSearchUser>[];
  int _offset = 0;
  bool _busy = false, _more = true;
  String? _error;
  bool get current =>
      mounted && identical(repository, ref.read(neteaseUserRepositoryProvider));
  @override
  void initState() {
    super.initState();
    unawaited(Future<void>.microtask(_load));
  }

  Future<void> _load() async {
    if (_busy || !_more || !current) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await repository.connections(
        widget.user.id,
        followers: widget.followers,
        offset: _offset,
      );
      if (!current) return;
      setState(() {
        final ids = _users.map((v) => v.id).toSet();
        _users.addAll(page.items.where((v) => ids.add(v.id)));
        _offset += page.consumed;
        _more = page.more;
      });
    } catch (_) {
      if (current) setState(() => _error = '暂时无法加载，点此重试');
    } finally {
      if (current) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(neteaseUserRepositoryProvider);
    return PlatformPageFrame(
      title: widget.followers ? '粉丝' : '关注',
      child: !current
          ? const Center(child: Text('账号已变化，请返回后重新打开'))
          : NotificationListener<ScrollNotification>(
              onNotification: (event) {
                if (event.metrics.extentAfter < 240 && _error == null) {
                  unawaited(_load());
                }
                return false;
              },
              child: ListView.builder(
                padding: BetaContentInsets.musicPaddingOf(
                  context,
                  EdgeInsets.only(top: 8, bottom: 180),
                ),
                itemCount: _users.length + 1,
                itemBuilder: (context, index) {
                  if (index < _users.length) {
                    return NeteaseSearchUserRow(user: _users[index]);
                  }
                  if (_busy) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: ArtworkPendingContent(
                        child: Center(child: BetaActivityIndicator()),
                      ),
                    );
                  }
                  if (_error != null) {
                    return TextButton(onPressed: _load, child: Text(_error!));
                  }
                  if (_more) {
                    return Center(
                      child: BetaGlassButton(
                        onPressed: _load,
                        child: const Text('加载更多用户'),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(_users.isEmpty ? '暂无可查看的用户' : '已显示全部用户'),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
