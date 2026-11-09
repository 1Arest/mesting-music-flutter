import '../../themes/music_typography.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_popup_menu_button.dart';
import '../presentation/platform_avatar.dart';
import 'qishui_models.dart';

enum QishuiMineTab { playlists, downloads, history }

extension QishuiMineTabLabel on QishuiMineTab {
  String get label => switch (this) {
    QishuiMineTab.playlists => '歌单',
    QishuiMineTab.downloads => '下载',
    QishuiMineTab.history => '历史播放',
  };
}

/// Mine follows the official content hierarchy while retaining Mesting's
/// floating glass controls. The cover wall is drawn only from this account's
/// returned playlists. A missing official statistic remains unknown, never 0.
class QishuiMineHeader extends StatelessWidget {
  const QishuiMineHeader({
    required this.nickname,
    required this.avatar,
    required this.playlists,
    required this.onAccount,
    required this.onMembership,
    required this.onEffects,
    required this.onSwitchPlatform,
    required this.onSettings,
    this.following,
    this.followers,
    this.likes,
    this.listeningLabel,
    this.onFollowing,
    this.onFollowers,
    this.onLikes,
    this.onListening,
    super.key,
  });
  final String nickname, avatar;
  final List<QishuiPlaylist> playlists;
  final VoidCallback onAccount, onMembership, onEffects;
  final VoidCallback onSwitchPlatform, onSettings;
  final int? following, followers, likes;
  final String? listeningLabel;
  final VoidCallback? onFollowing, onFollowers, onLikes, onListening;

  Widget _stat(
    BuildContext context,
    String label,
    int? count,
    VoidCallback? open,
  ) => TextButton(
    onPressed: open,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      minimumSize: const Size(48, 48),
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      textStyle: Theme.of(context).textTheme.labelLarge,
    ),
    child: Semantics(
      label: '$label${count == null ? '数尚未取得' : ' $count'}',
      child: ExcludeSemantics(child: Text('${count ?? '—'} $label')),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: _QishuiMineCoverWall(playlists: playlists),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('听歌总时长', style: theme.textTheme.labelLarge),
                            const SizedBox(height: 6),
                            TextButton(
                              key: const ValueKey('qishui-official-listening'),
                              onPressed: onListening,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(48, 48),
                                alignment: Alignment.centerLeft,
                              ),
                              child: Semantics(
                                label: '官方听歌总时长 ${listeningLabel ?? '尚未取得'}',
                                child: ExcludeSemantics(
                                  child: Text(
                                    listeningLabel ?? '—',
                                    style: theme.textTheme.headlineMedium,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      BetaPopupMenuButton<String>(
                        tooltip: '我的菜单',
                        icon: const Icon(Icons.menu_rounded),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'account', child: Text('汽水账号')),
                          PopupMenuItem(value: 'platform', child: Text('切换平台')),
                          PopupMenuItem(value: 'settings', child: Text('设置')),
                        ],
                        onSelected: (value) {
                          switch (value) {
                            case 'account':
                              onAccount();
                            case 'platform':
                              onSwitchPlatform();
                            case 'settings':
                              onSettings();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 90),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: onAccount,
                          borderRadius: BorderRadius.circular(38),
                          child: Semantics(
                            label: '汽水账号资料',
                            button: true,
                            child: PlatformAvatar(url: avatar, size: 76),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: onAccount,
                                child: Text(
                                  nickname.isEmpty ? '汽水账号' : nickname,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        fontWeight: MusicTypography.titleWeight,
                                      ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  _stat(context, '关注', following, onFollowing),
                                  _stat(context, '粉丝', followers, onFollowers),
                                  _stat(context, '获赞', likes, onLikes),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 320 &&
                  MediaQuery.textScalerOf(context).scale(15) > 20;
              final cards = [
                BetaGlassButton(
                  onPressed: onMembership,
                  child: const Text('会员与免费听', textAlign: TextAlign.center),
                ),
                BetaGlassButton(
                  onPressed: onEffects,
                  child: const Text('官版音效', textAlign: TextAlign.center),
                ),
              ];
              return stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        cards[0],
                        const SizedBox(height: 12),
                        cards[1],
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 12),
                        Expanded(child: cards[1]),
                      ],
                    );
            },
          ),
        ),
        Divider(
          height: 1,
          indent: 24,
          endIndent: 24,
          color: colors.outlineVariant.withValues(alpha: .3),
        ),
      ],
    );
  }
}

/// Mutation callbacks belong to the root's retained-account scope. The toolbar
/// only renders their controls and never starts an unaudited network request.
class QishuiMinePlaylistToolbar extends StatelessWidget {
  const QishuiMinePlaylistToolbar({
    required this.onCreate,
    required this.onImport,
    this.busy = false,
    super.key,
  });
  final VoidCallback onCreate, onImport;
  final bool busy;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text('创建的歌单', style: Theme.of(context).textTheme.titleSmall),
        Wrap(
          spacing: 8,
          children: [
            BetaGlassButton(
              height: 46,
              horizontalPadding: 12,
              interactionEnabled: !busy,
              onPressed: onImport,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.input_rounded, size: 18),
                  SizedBox(width: 6),
                  Text('导入'),
                ],
              ),
            ),
            BetaGlassButton(
              height: 46,
              horizontalPadding: 12,
              interactionEnabled: !busy,
              onPressed: onCreate,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 18),
                  SizedBox(width: 6),
                  Text('创建'),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _QishuiMineCoverWall extends StatelessWidget {
  const _QishuiMineCoverWall({required this.playlists});
  final List<QishuiPlaylist> playlists;
  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final covers = playlists.where((p) => p.cover.isNotEmpty).take(6).toList();
    return Stack(
      fit: StackFit.expand,
      children: [
        if (covers.isNotEmpty)
          ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: 420,
              child: Transform.rotate(
                angle: -.09,
                child: GridView.count(
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [
                    for (final list in covers)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: ArtworkImage(uri: list.cover),
                      ),
                  ],
                ),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                surface.withValues(alpha: .55),
                surface.withValues(alpha: .9),
                surface,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class QishuiMineTabs extends StatelessWidget {
  const QishuiMineTabs({
    required this.selected,
    required this.onSelected,
    super.key,
  });
  final QishuiMineTab selected;
  final ValueChanged<QishuiMineTab> onSelected;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Row(
      children: [
        for (final tab in QishuiMineTab.values)
          Semantics(
            selected: tab == selected,
            child: TextButton(
              onPressed: () => onSelected(tab),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tab.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: tab == selected
                            ? MusicTypography.titleWeight
                            : FontWeight.w500,
                        color: tab == selected
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 18,
                      height: 3,
                      decoration: BoxDecoration(
                        color: tab == selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Kept separate from loading and mutations so list rows never own a second
/// account cache. Both special and user-created playlists open the same detail.
class QishuiMinePlaylistList extends StatelessWidget {
  const QishuiMinePlaylistList({
    required this.playlists,
    required this.open,
    super.key,
  });
  final List<QishuiPlaylist> playlists;
  final ValueChanged<QishuiPlaylist> open;
  @override
  Widget build(BuildContext context) => SliverList.builder(
    itemCount: playlists.length,
    itemBuilder: (context, i) {
      final list = playlists[i];
      return ListTile(
        key: ValueKey('qishui-mine-playlist-${list.id}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        minVerticalPadding: 10,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: SizedBox.square(
            dimension: 62,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ArtworkImage(uri: list.cover),
                if (list.kind == 1)
                  const Icon(
                    Icons.favorite_rounded,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 12)],
                  ),
              ],
            ),
          ),
        ),
        title: Text(
          list.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: MusicTypography.titleWeight,
          ),
        ),
        subtitle: Text('${list.count} 首'),
        onTap: () => open(list),
      );
    },
  );
}
