import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/beta_glass_controls.dart';

/// One established red action, while collection loading stays with its owner.
class PlatformPlayAllButton extends StatelessWidget {
  const PlatformPlayAllButton({
    required this.onPressed,
    this.loading = false,
    super.key,
  });
  final VoidCallback? onPressed;
  final bool loading;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    key: const ValueKey('platform-play-all'),
    style: FilledButton.styleFrom(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFE92350)
          : const Color(0xFFD61643),
      foregroundColor: Colors.white,
      minimumSize: const Size(120, 48),
    ),
    onPressed: loading ? null : onPressed,
    icon: loading
        ? const BetaActivityIndicator()
        : const Icon(CupertinoIcons.play_fill, size: 18),
    label: Text(loading ? '正在准备…' : '播放全部'),
  );
}
