import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/branded_launch_screen.dart';
import '../../app/startup_video_surface.dart';
import '../../app/startup_image_surface.dart';
import '../../shared/widgets/beta_glass_controls.dart';
import '../../shared/widgets/music_notice.dart';
import '../../shared/widgets/beta_press_surface.dart';
import 'startup_style.dart';

/// Static posters keep scrolling cheap and silent. Each explicit preview owns
/// one video controller and releases it when the preview route is dismissed.
class StartupStylePicker extends ConsumerStatefulWidget {
  const StartupStylePicker({super.key});

  @override
  ConsumerState<StartupStylePicker> createState() => _StartupStylePickerState();
}

class _StartupStylePickerState extends ConsumerState<StartupStylePicker> {
  bool _saving = false;
  bool _previewing = false;

  Future<void> _select(StartupStyle style) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(startupStyleProvider.notifier).select(style);
    } on Object {
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.error_outline_rounded,
          title: '启动页未能保存',
          message: '请稍后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _preview(StartupStyle style) async {
    if (_previewing) return;
    _previewing = true;
    try {
      await showGeneralDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: true,
        barrierLabel: '关闭启动页预览',
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 240),
        transitionBuilder: (context, animation, secondary, child) =>
            FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: ScaleTransition(
                scale: Tween(begin: .96, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: child,
              ),
            ),
        pageBuilder: (context, _, secondary) => SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: style == StartupStyle.classic
                        ? const MestingBrandedLaunchScreen(forceCoral: true)
                        : style.staticImage
                        ? StartupImageSurface(style: style)
                        : StartupVideoSurface(style: style, onFinished: () {}),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: BetaGlassButton(
                      label: '关闭预览',
                      height: 48,
                      width: 48,
                      child: const Icon(CupertinoIcons.xmark),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      _previewing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(startupStyleProvider);
    final color = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final style in StartupStyle.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    selected: selected == style,
                    button: true,
                    child: BetaPressSurface(
                      key: ValueKey('startup-style-${style.id}'),
                      onTap: _saving ? null : () => _select(style),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 54,
                                height: 80,
                                child: ColoredBox(
                                  color: mestingBrandCoral,
                                  child: style.posterAsset != null
                                      ? Image.asset(
                                          style.posterAsset!,
                                          fit: BoxFit.cover,
                                          cacheWidth: 180,
                                        )
                                      : Image.asset(mestingLaunchLockupAsset),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                style == StartupStyle.staticOne
                                    ? '${style.label}（默认）'
                                    : style.label,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 240),
                              transitionBuilder: (child, animation) =>
                                  ScaleTransition(
                                    scale: animation,
                                    child: FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                  ),
                              child: Icon(
                                key: ValueKey(selected == style),
                                selected == style
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.circle,
                                color: selected == style
                                    ? color.primary
                                    : color.onSurfaceVariant,
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: '预览${style.label}',
                  onPressed: () => _preview(style),
                  icon: const Icon(CupertinoIcons.play_circle, size: 28),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
