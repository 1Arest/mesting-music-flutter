import '../../../../shared/widgets/beta_content_insets.dart';
import '../../../../shared/widgets/beta_page_motion.dart';
import 'together_sync_diagnostics_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/audio/playback_providers.dart';
import '../../../../shared/models/track.dart';
import '../../../../shared/widgets/beta_glass_action.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../../experience/presentation/editorial_widgets.dart';
import '../../presentation/platform_design.dart';
import '../messages/netease_messages_repository.dart';
import '../messages/netease_messages_page.dart';
import 'netease_together_controller.dart';
import 'netease_together_player_header.dart';
import 'netease_together_exit.dart';
import '../../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../themes/music_application_theme.dart';
import 'together_room_members.dart';
import '../../../themes/music_typography.dart';

Future<void> showNeteaseTogetherPanel(
  BuildContext context, {
  NeteasePerson? invitee,
  String? invitation,
}) {
  // A player forces its artwork chrome dark; this account/room sheet follows
  // the application's selected appearance, including its optical surface.
  final applicationContext = Navigator.of(context, rootNavigator: true).context;
  return showLiquidGlassBottomSheet<void>(
    context: applicationContext,
    themeBuilder: MusicApplicationTheme.of,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .86,
      child: NeteaseTogetherPanel(invitee: invitee, invitation: invitation),
    ),
  );
}

class NeteaseTogetherPanel extends ConsumerStatefulWidget {
  const NeteaseTogetherPanel({this.invitee, this.invitation, super.key});
  final NeteasePerson? invitee;
  final String? invitation;
  @override
  ConsumerState<NeteaseTogetherPanel> createState() =>
      _NeteaseTogetherPanelState();
}

class _NeteaseTogetherPanelState extends ConsumerState<NeteaseTogetherPanel> {
  List<NeteasePerson> _friends = [];
  String? _invitation, _friendError, _localNotice;
  bool _loadingFriends = true;
  @override
  void initState() {
    super.initState();
    _invitation = widget.invitation;
    Future.microtask(() async {
      await ref.read(neteaseTogetherControllerProvider)?.restore();
      await _loadFriends();
    });
  }

  Future<void> _loadFriends() async {
    final repository = ref.read(neteaseMessagesRepositoryProvider);
    try {
      final friends = await repository.friends();
      if (mounted &&
          ref.read(neteaseMessagesRepositoryProvider) == repository) {
        setState(() {
          _friends = friends;
          _friendError = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _friendError = '好友列表暂时无法加载');
    } finally {
      if (mounted) setState(() => _loadingFriends = false);
    }
  }

  Future<void> _chooseFriend(NeteaseTogetherController controller) async {
    final peer = await Navigator.of(context).push<NeteasePerson>(
      MestingPageRoute(builder: (_) => const NeteaseFriendsPage()),
    );
    if (peer != null && mounted) await controller.invite(peer);
  }

  Future<void> _pasteInvitation() async {
    final value = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (NeteaseTogetherInvitation.parse(value?.text ?? '') == null) {
      setState(() => _localNotice = '剪贴板中没有网易云一起听邀请链接');
    } else {
      setState(() {
        _invitation = value!.text;
        _localNotice = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(neteaseTogetherControllerProvider);
    final track = ref.watch(currentTrackProvider);
    if (controller == null) {
      return const PlatformPageFrame(
        title: '一起听',
        child: Center(child: Text('请先登录网易云账号')),
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Theme(
        data: MusicApplicationTheme.of(context),
        child: PlatformPageFrame(
          title: '一起听',
          subtitle: controller.active ? '房间成员与共享设置' : '邀请朋友，一起分享此刻的音乐',
          actions: [
            BetaGlassAction(
              label: '同步诊断',
              icon: CupertinoIcons.doc_text_search,
              blue: false,
              onPressed: () => Navigator.of(context).push(
                betaContentRoute<void>(
                  TogetherSyncDiagnosticsPage(controller: controller),
                ),
              ),
            ),
            BetaGlassAction(
              label: '刷新一起听',
              icon: CupertinoIcons.refresh,
              blue: false,
              loading: controller.busy,
              onPressed: controller.restore,
            ),
          ],
          child: ListView(
            padding: BetaContentInsets.musicPaddingOf(
              context,
              const EdgeInsets.fromLTRB(22, 12, 22, 32),
            ),
            children: [
              if (track.source == TrackSource.netease)
                EditorialTrackRow(track: track, contextTracks: [track]),
              if (controller.active) ...[
                const SizedBox(height: 16),
                PlatformPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '正在一起听',
                        style: TextStyle(
                          fontSize: MusicTypography.headingSize,
                          fontWeight: MusicTypography.titleWeight,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TogetherRoomMembers(
                        self:
                            controller.members
                                .where((p) => p.id == controller.self.id)
                                .firstOrNull ??
                            controller.self,
                        peer: controller.peers.firstOrNull,
                      ),
                      if (controller.peers.isEmpty) ...[
                        const SizedBox(height: 10),
                        const Text('等待朋友加入…'),
                      ],
                      const SizedBox(height: 10),
                      const Text('离开此页面后仍会继续同步，退出一起听后停止同步。'),
                      const SizedBox(height: 14),
                      BetaGlassButton(
                        key: const ValueKey('together-panel-exit'),
                        loading: controller.ending,
                        onPressed: controller.busy
                            ? null
                            : () => confirmNeteaseTogetherExit(
                                context,
                                controller,
                              ),
                        child: const Text('退出一起听'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    controller.locationEnabled
                        ? controller.distance.label
                        : '双方距离',
                  ),
                  subtitle: Text(
                    controller.presenceNotice ??
                        (controller.locationEnabled
                            ? '当前房间已开启位置共享'
                            : '双方开启位置后显示距离'),
                  ),
                  trailing: TextButton(
                    onPressed: controller.locating
                        ? null
                        : controller.locationEnabled
                        ? controller.disableLocation
                        : () => requestTogetherLocation(context, controller),
                    child: Text(
                      controller.locating
                          ? '获取中…'
                          : controller.locationEnabled
                          ? '关闭共享'
                          : '开启位置',
                    ),
                  ),
                ),
                if (controller.locationEnabled)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: controller.locating
                          ? null
                          : controller.enableLocation,
                      icon: const Icon(CupertinoIcons.refresh, size: 18),
                      label: const Text('刷新当前位置'),
                    ),
                  ),
                if (controller.canInvitePeer)
                  BetaGlassButton(
                    onPressed: controller.busy
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(text: controller.invitationLink),
                            );
                            if (mounted) {
                              setState(
                                () => _localNotice = '邀请链接已复制，可发送给网易云官版好友',
                              );
                            }
                          },
                    child: const Text('复制邀请链接'),
                  ),
                if (controller.canInvitePeer) const SizedBox(height: 12),
                BetaGlassButton(
                  onPressed: controller.busy
                      ? null
                      : controller.shareCurrentQueue,
                  child: const Text('共享当前待播列表'),
                ),
              ],
              if (_invitation != null && !controller.active) ...[
                const SizedBox(height: 16),
                PlatformPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('朋友邀请你一起听'),
                      const SizedBox(height: 12),
                      BetaGlassButton(
                        blue: true,
                        loading: controller.busy,
                        onPressed: () => controller.join(_invitation!),
                        child: const Text('接受邀请'),
                      ),
                    ],
                  ),
                ),
              ],
              if (controller.canInvitePeer) ...[
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '邀请好友',
                        style: TextStyle(
                          fontSize: MusicTypography.headingSize,
                          fontWeight: MusicTypography.titleWeight,
                        ),
                      ),
                    ),
                    BetaGlassAction(
                      label: '查找朋友',
                      icon: CupertinoIcons.search,
                      blue: false,
                      onPressed: controller.busy
                          ? null
                          : () => _chooseFriend(controller),
                    ),
                  ],
                ),
                if (widget.invitee != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: NeteasePersonAvatar(widget.invitee!),
                    title: Text(
                      widget.invitee!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: BetaGlassAction(
                      label: '邀请${widget.invitee!.name}一起听',
                      icon: CupertinoIcons.add,
                      onPressed: controller.busy
                          ? null
                          : () => controller.invite(widget.invitee!),
                    ),
                  ),
                if (_loadingFriends)
                  const Padding(
                    padding: EdgeInsets.all(22),
                    child: Center(child: BetaActivityIndicator()),
                  ),
                if (_friendError != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_friendError!),
                  ),
                for (final friend in _friends.where(
                  (p) => p.id != widget.invitee?.id,
                ))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: NeteasePersonAvatar(friend),
                    title: Text(
                      friend.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: BetaGlassAction(
                      label: '邀请${friend.name}一起听',
                      icon: CupertinoIcons.add,
                      onPressed: controller.busy
                          ? null
                          : () => controller.invite(friend),
                    ),
                  ),
                const SizedBox(height: 12),
                BetaGlassButton(
                  onPressed: controller.busy
                      ? null
                      : () => _chooseFriend(controller),
                  child: const Text('选择更多朋友'),
                ),
              ],
              if (!controller.active) ...[
                const SizedBox(height: 12),
                BetaGlassButton(
                  onPressed: controller.busy ? null : _pasteInvitation,
                  child: const Text('粘贴邀请链接加入'),
                ),
                const SizedBox(height: 12),
                BetaGlassButton(
                  onPressed: controller.busy ? null : controller.create,
                  child: const Text('开始一起听'),
                ),
              ],
              if (controller.sharedTracks.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  '共享待播列表',
                  style: TextStyle(
                    fontSize: MusicTypography.headingSize,
                    fontWeight: MusicTypography.titleWeight,
                  ),
                ),
                for (final song in controller.sharedTracks)
                  EditorialTrackRow(
                    track: song,
                    contextTracks: controller.sharedTracks,
                  ),
              ],
              if (controller.notice != null || _localNotice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(controller.notice ?? _localNotice!),
                ),
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(controller.error!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
