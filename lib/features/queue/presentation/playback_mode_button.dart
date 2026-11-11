import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/audio/playback_mode.dart';

IconData queueModeIcon(PlaybackMode mode) => switch (mode) {
  PlaybackMode.sequential => CupertinoIcons.arrow_up_arrow_down,
  PlaybackMode.list => CupertinoIcons.repeat,
  PlaybackMode.single => CupertinoIcons.repeat_1,
  PlaybackMode.random => CupertinoIcons.shuffle,
};

/// A single entry shows the current mode and all four mutually exclusive choices.
class PlaybackModeButton extends StatelessWidget {
  const PlaybackModeButton({
    required this.mode,
    required this.onSelected,
    this.immersive = false,
    super.key,
  });

  final PlaybackMode mode;
  final ValueChanged<PlaybackMode> onSelected;
  final bool immersive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ink = immersive ? Colors.white : colors.onSurface;
    return PopupMenuButton<PlaybackMode>(
      key: const ValueKey('queue-playback-mode'),
      tooltip: '播放模式：${mode.label}',
      initialValue: mode,
      color: immersive ? const Color(0xFF25262C) : colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final choice in PlaybackMode.values)
          PopupMenuItem<PlaybackMode>(
            key: ValueKey('queue-mode-${choice.name}'),
            value: choice,
            child: Semantics(
              selected: choice == mode,
              child: Row(
                children: [
                  Icon(queueModeIcon(choice), color: ink, size: 21),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(choice.label, style: TextStyle(color: ink)),
                  ),
                  const SizedBox(width: 16),
                  if (choice == mode)
                    Icon(Icons.check_rounded, color: ink, size: 19)
                  else
                    const SizedBox(width: 19),
                ],
              ),
            ),
          ),
      ],
      child: Semantics(
        button: true,
        label: '当前${mode.label}，选择播放模式',
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: ink.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(queueModeIcon(mode), color: ink, size: 20),
              const SizedBox(width: 7),
              Text(mode.label, style: TextStyle(color: ink, fontSize: 13)),
              const SizedBox(width: 5),
              Icon(
                CupertinoIcons.chevron_down,
                color: ink.withValues(alpha: .7),
                size: 11,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
