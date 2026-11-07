import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../messages/netease_messages_page.dart';
import '../messages/netease_messages_repository.dart';
import 'netease_together_controller.dart';
import '../../../themes/music_typography.dart';

Future<void> requestTogetherLocation(
  BuildContext context,
  NeteaseTogetherController controller,
) async {
  final accepted = await showCupertinoDialog<bool>(
    context: context,
    builder: (c) => CupertinoAlertDialog(
      title: const Text('开启位置查看距离', style: MusicTypography.titleEmphasis),
      content: const Text(
        '本次位置会发送给网易云，用于计算你与房间好友的距离。只在你主动操作时获取，不在后台持续定位。双方开启后才能显示距离，可随时在房间面板关闭共享。',
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('暂不开启', style: MusicTypography.regularText),
        ),
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('开启位置', style: MusicTypography.regularText),
        ),
      ],
    ),
  );
  if (accepted == true && context.mounted) await controller.enableLocation();
}

/// Only the room island listens to room changes. Its small duration label owns
/// its clock; artwork, shader surfaces and transport never rebuild on a tick.
class NeteaseTogetherPlayerHeader extends ConsumerStatefulWidget {
  const NeteaseTogetherPlayerHeader({
    required this.onManage,
    this.foreground = Colors.white,
    super.key,
  });
  final VoidCallback onManage;
  final Color foreground;
  @override
  ConsumerState<NeteaseTogetherPlayerHeader> createState() =>
      _TogetherHeaderState();
}

class _TogetherHeaderState extends ConsumerState<NeteaseTogetherPlayerHeader> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(neteaseTogetherControllerProvider, (previous, next) {
      if (next != null) Future.microtask(next.restore);
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(neteaseTogetherControllerProvider);
    if (controller == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.active) return const SizedBox.shrink();
        final self =
            controller.members
                .where((p) => p.id == controller.self.id)
                .firstOrNull ??
            controller.self;
        final peer = controller.peers.firstOrNull;
        return Padding(
          key: const ValueKey('player-together-header'),
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                label: peer == null
                    ? '一起听，等待朋友加入，管理房间'
                    : '与${peer.name}一起听，管理房间',
                child: InkResponse(
                  onTap: widget.onManage,
                  radius: 60,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 5,
                    ),
                    child: SizedBox(
                      width: 104,
                      height: 60,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            top: 3,
                            child: _Portrait(person: self),
                          ),
                          Positioned(
                            right: 0,
                            top: 3,
                            child: _Portrait(person: peer),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (peer == null)
                Text(
                  '等待朋友加入',
                  style: TextStyle(
                    color: widget.foreground,
                    fontSize: MusicTypography.subheadlineSize,
                  ),
                )
              else if (controller.error != null)
                Text(
                  '连接暂时中断，正在重连',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: widget.foreground,
                    fontSize: MusicTypography.footnoteSize,
                  ),
                )
              else
                _TogetherElapsed(
                  controller: controller,
                  foreground: widget.foreground,
                ),
              TextButton(
                key: const ValueKey('together-distance-action'),
                onPressed: controller.locating
                    ? null
                    : controller.locationEnabled
                    ? widget.onManage
                    : () => requestTogetherLocation(context, controller),
                style: TextButton.styleFrom(
                  foregroundColor: widget.foreground.withValues(alpha: .85),
                  disabledForegroundColor: widget.foreground.withValues(
                    alpha: .7,
                  ),
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(
                  controller.locating
                      ? '正在获取位置…'
                      : controller.locationEnabled
                      ? controller.distance.label
                      : '开启位置查看距离',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: MusicTypography.footnoteSize,
                  ),
                ),
              ),
              if (controller.presenceNotice != null)
                Text(
                  controller.presenceNotice!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: widget.foreground,
                    fontSize: MusicTypography.captionSize,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({this.person});
  final NeteasePerson? person;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Theme.of(context).colorScheme.surface,
    ),
    child: person == null
        ? const SizedBox.square(
            dimension: 52,
            child: Icon(
              CupertinoIcons.person_add,
              color: Colors.white70,
              size: 25,
            ),
          )
        : NeteasePersonAvatar(person!, size: 52),
  );
}

class _TogetherElapsed extends StatefulWidget {
  const _TogetherElapsed({required this.controller, required this.foreground});
  final NeteaseTogetherController controller;
  final Color foreground;
  @override
  State<_TogetherElapsed> createState() => _TogetherElapsedState();
}

class _TogetherElapsedState extends State<_TogetherElapsed> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      widget.controller.togetherDurationLabel,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: MusicTypography.subheadlineSize,
        color: widget.foreground,
      ),
    );
  }
}
