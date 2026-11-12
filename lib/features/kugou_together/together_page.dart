import '../../shared/widgets/music_notice.dart';
import '../../shared/widgets/beta_content_insets.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/playback_providers.dart';
import '../../core/platform/share_bridge.dart';
import '../../shared/widgets/artwork_image.dart';
import '../../shared/widgets/beta_glass_controls.dart';
import '../auth/presentation/beta_login_navigation.dart';
import '../music_platform/presentation/platform_design.dart';
import '../music_platform/presentation/platform_feedback.dart';
import 'together_controller.dart';
import 'together_models.dart';
import '../themes/music_typography.dart';

class TogetherPage extends ConsumerStatefulWidget {
  const TogetherPage({super.key});
  @override
  ConsumerState<TogetherPage> createState() => _TogetherPageState();
}

class _TogetherPageState extends ConsumerState<TogetherPage> {
  TogetherController? _loadedController;
  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(togetherControllerProvider);
    if (_loadedController != controller) {
      _loadedController = controller;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _loadedController == controller) {
          unawaited(controller.loadRooms());
        }
      });
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => PlatformPageFrame(
        title: '一起听',
        subtitle: controller.active ? controller.room!.name : '把此刻的音乐分享给彼此',
        actions: [
          BetaGlassButton(
            label: '刷新一起听',
            width: 48,
            height: 48,
            onPressed: controller.busy
                ? null
                : () => controller.active
                      ? controller.refresh()
                      : controller.loadRooms(),
            child: const Icon(CupertinoIcons.arrow_clockwise, size: 21),
          ),
        ],
        child: !controller.signedIn
            ? _login(context)
            : CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (controller.active)
                            _roomHeader(context, controller)
                          else
                            _lobbyHeader(context, controller),
                          if (controller.error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: _message(
                                context,
                                controller.error!,
                                retry: controller.active
                                    ? controller.refresh
                                    : null,
                              ),
                            ),
                          const SizedBox(height: 24),
                          PlatformSectionTitle(
                            controller.active ? '房间歌单' : '正在一起听',
                            subtitle: controller.active
                                ? controller.owner
                                      ? '点击歌曲切换全房间的音乐'
                                      : '播放由房主同步'
                                : '进入一个正在播放音乐的房间',
                          ),
                          if (!controller.active && controller.loadingRooms)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: BetaActivityIndicator(),
                              ),
                            ),
                          if (!controller.active &&
                              controller.roomsError != null)
                            _message(
                              context,
                              controller.roomsError!,
                              retry: controller.loadRooms,
                            ),
                          if (!controller.active &&
                              !controller.loadingRooms &&
                              controller.roomsError == null &&
                              controller.rooms.isEmpty)
                            _message(context, '暂时没有可加入的房间，你可以创建一个私密房间。'),
                          if (controller.active && controller.songs.isEmpty)
                            _message(
                              context,
                              '房间暂未返回歌曲，请刷新重试。',
                              retry: controller.refresh,
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    sliver: controller.active
                        ? SliverList.builder(
                            itemCount: controller.songs.length,
                            itemBuilder: (context, index) {
                              final song = controller.songs[index];
                              final selected = song.matches(
                                controller.remote?.hash ?? '',
                                controller.remote?.mixId ?? '',
                              );
                              return _song(
                                context,
                                controller,
                                song,
                                index,
                                selected,
                              );
                            },
                          )
                        : SliverList.builder(
                            itemCount: controller.rooms.length,
                            itemBuilder: (context, index) => _room(
                              context,
                              controller,
                              controller.rooms[index],
                            ),
                          ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: BetaContentInsets.musicBottomOf(context, 160),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _login(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.person_2_fill, size: 58),
          const SizedBox(height: 18),
          Text(
            '登录后，一起听同一首歌',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text('使用酷狗账号创建和加入房间。', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          BetaGlassButton(
            blue: true,
            onPressed: () =>
                openBetaLogin(context, redirect: '/music/together'),
            child: const Text('登录酷狗账号'),
          ),
        ],
      ),
    ),
  );

  Widget _lobbyHeader(BuildContext context, TogetherController controller) =>
      PlatformPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              CupertinoIcons.person_2_fill,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '同一首歌，同一个此刻。',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: MusicTypography.titleWeight,
              ),
            ),
            const SizedBox(height: 10),
            const Text('创建私密房间，分享房间号邀请朋友；也可以直接加入已有房间。'),
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 12,
              children: [
                BetaGlassButton(
                  blue: true,
                  loading: controller.busy,
                  onPressed: controller.busy
                      ? null
                      : () => _input(controller, create: true),
                  child: const Text('创建房间'),
                ),
                BetaGlassButton(
                  onPressed: controller.busy
                      ? null
                      : () => _input(controller, create: false),
                  child: const Text('加入房间'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: controller.busy ? null : controller.restore,
              child: const Text('恢复当前账号的房间'),
            ),
          ],
        ),
      );

  Widget _roomHeader(BuildContext context, TogetherController controller) {
    final room = controller.room!;
    final stamp = controller.lastSync;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PlatformPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.person_2_fill, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      controller.owner ? '你是房主' : '正在跟随房主',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                  ),
                  if (controller.busy) const BetaActivityIndicator(),
                ],
              ),
              const SizedBox(height: 14),
              SelectableText('房间号：${room.id}'),
              const SizedBox(height: 8),
              Text(
                stamp == null
                    ? '正在连接房间…'
                    : '上次同步 ${stamp.hour.toString().padLeft(2, '0')}:${stamp.minute.toString().padLeft(2, '0')}:${stamp.second.toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  BetaGlassButton(
                    height: 46,
                    onPressed: () async {
                      try {
                        await ShareBridge.shareText(
                          '来 Mesting Music 一起听，房间号：${room.id}',
                          title: '邀请一起听',
                        );
                      } catch (_) {
                        await Clipboard.setData(ClipboardData(text: room.id));
                        if (context.mounted) {
                          showMusicNotice(
                            context,
                            icon: Icons.check_rounded,
                            title: '房间号已复制',
                            message: '',
                          );
                        }
                      }
                    },
                    child: const Text('邀请朋友'),
                  ),
                  BetaGlassButton(
                    height: 46,
                    onPressed: controller.busy
                        ? null
                        : () => _leave(controller),
                    child: Text(controller.owner ? '结束房间' : '离开房间'),
                  ),
                  if (controller.owner)
                    BetaGlassButton(
                      height: 46,
                      onPressed: controller.busy ? null : controller.addCurrent,
                      child: const Text('加入当前待播'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (controller.detached)
          PlatformPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('已暂停跟随房间'),
                const SizedBox(height: 8),
                const Text('本机播放操作不会改变房主的播放。准备好后可重新跟随。'),
                const SizedBox(height: 14),
                BetaGlassButton(
                  blue: true,
                  onPressed: controller.follow,
                  child: const Text('重新跟随'),
                ),
              ],
            ),
          ),
        if (controller.owner) _OwnerControls(controller: controller),
        if (controller.members.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            '房间成员',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: MusicTypography.titleWeight,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 83,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: controller.members.length,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder: (context, index) {
                final member = controller.members[index];
                return SizedBox(
                  width: 60,
                  child: Column(
                    children: [
                      ClipOval(
                        child: member.avatar.isEmpty
                            ? Container(
                                width: 48,
                                height: 48,
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                child: const Icon(CupertinoIcons.person_fill),
                              )
                            : ArtworkImage(
                                uri: member.avatar,
                                width: 48,
                                height: 48,
                                decodeWidth: 96,
                              ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        member.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _message(
    BuildContext context,
    String message, {
    Future<void> Function()? retry,
  }) => PlatformPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        if (retry != null) ...[
          const SizedBox(height: 10),
          TextButton(onPressed: retry, child: const Text('重试')),
        ],
      ],
    ),
  );

  Widget _room(
    BuildContext context,
    TogetherController controller,
    TogetherRoom room,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: controller.busy ? null : () => controller.join(room.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: room.cover.isEmpty
                    ? SizedBox(
                        width: 64,
                        height: 64,
                        child: Icon(
                          CupertinoIcons.person_2_fill,
                          color: Theme.of(context).colorScheme.primary,
                          size: 32,
                        ),
                      )
                    : ArtworkImage(
                        uri: room.cover,
                        width: 64,
                        height: 64,
                        decodeWidth: 128,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      room.memberCount == null
                          ? '房间号 ${room.id}'
                          : '${room.memberCount} 人在线',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(CupertinoIcons.chevron_forward, size: 17),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _song(
    BuildContext context,
    TogetherController controller,
    TogetherSong song,
    int index,
    bool selected,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 4),
    leading: song.cover.isEmpty
        ? SizedBox(width: 48, child: Center(child: Text('${index + 1}')))
        : ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ArtworkImage(
              uri: song.cover,
              width: 48,
              height: 48,
              decodeWidth: 96,
            ),
          ),
    title: Text(
      song.track.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: MusicTypography.titleWeight,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
    ),
    subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: selected
        ? Icon(
            CupertinoIcons.speaker_2_fill,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          )
        : null,
    onTap: controller.owner && !controller.busy
        ? () => controller.select(song)
        : null,
  );

  Future<void> _input(
    TogetherController controller, {
    required bool create,
  }) async {
    final value = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => _RoomInputDialog(create: create),
    );
    if (value == null || !mounted) return;
    if (create) {
      await controller.create(value);
    } else {
      await controller.join(value);
    }
  }

  Future<void> _leave(TogetherController controller) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: Text(
          controller.owner ? '结束一起听？' : '离开一起听？',
          style: MusicTypography.titleEmphasis,
        ),
        content: Text(controller.owner ? '房间将结束，其他成员也会离开。' : '将停止跟随这个房间。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消', style: MusicTypography.regularText),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('确认', style: MusicTypography.regularText),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await controller.leave();
  }
}

class _OwnerControls extends ConsumerWidget {
  const _OwnerControls({required this.controller});
  final TogetherController controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(
      playbackStateProvider.select((s) => s.value?.playing ?? false),
    );
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration = ref.watch(durationProvider).value ?? Duration.zero;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: PlatformPanel(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    controller.playback.current?.title ?? '房间音乐',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                BetaGlassButton(
                  label: playing ? '暂停全房间播放' : '继续全房间播放',
                  width: 48,
                  height: 48,
                  onPressed: controller.busy
                      ? null
                      : () async {
                          try {
                            await controller.playback.setPlaying(!playing);
                            await controller.refresh();
                          } catch (error) {
                            if (context.mounted) {
                              showPlatformFailure(context, error);
                            }
                          }
                        },
                  child: Icon(
                    playing
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                    size: 20,
                  ),
                ),
              ],
            ),
            if (duration > Duration.zero)
              Slider(
                value: position.inMilliseconds.toDouble().clamp(
                  0,
                  duration.inMilliseconds.toDouble(),
                ),
                max: duration.inMilliseconds.toDouble(),
                onChanged: (_) {},
                onChangeEnd: (value) async {
                  try {
                    await controller.playback.seek(
                      Duration(milliseconds: value.round()),
                    );
                    await controller.refresh();
                  } catch (error) {
                    if (context.mounted) showPlatformFailure(context, error);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _RoomInputDialog extends StatefulWidget {
  const _RoomInputDialog({required this.create});
  final bool create;
  @override
  State<_RoomInputDialog> createState() => _RoomInputDialogState();
}

class _RoomInputDialogState extends State<_RoomInputDialog> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
    title: Text(
      widget.create ? '创建私密房间' : '加入一起听',
      style: MusicTypography.titleEmphasis,
    ),
    content: Padding(
      padding: const EdgeInsets.only(top: 16),
      child: CupertinoTextField(
        controller: input,
        autofocus: true,
        maxLength: widget.create ? 48 : 256,
        placeholder: widget.create ? '房间名称' : '房间号或邀请链接',
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) Navigator.pop(context, value);
        },
      ),
    ),
    actions: [
      CupertinoDialogAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消', style: MusicTypography.regularText),
      ),
      CupertinoDialogAction(
        onPressed: () {
          if (input.text.trim().isNotEmpty) Navigator.pop(context, input.text);
        },
        child: Text(
          widget.create ? '创建' : '加入',
          style: MusicTypography.regularText,
        ),
      ),
    ],
  );
}
