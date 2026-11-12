import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../music_platform/music_platform_providers.dart';
import '../music_platform/presentation/platform_avatar.dart';
import '../profile/presentation/vip_profile_effects.dart';
import 'profile_effect_style.dart';

/// An inline preview uses the same painter, avatar and playback meter as My.
class ProfileEffectPicker extends ConsumerStatefulWidget {
  const ProfileEffectPicker({super.key});

  @override
  ConsumerState<ProfileEffectPicker> createState() =>
      _ProfileEffectPickerState();
}

class _ProfileEffectPickerState extends ConsumerState<ProfileEffectPicker> {
  final _avatar = VipEffectAnchorHandle();
  bool _saving = false;

  Future<void> _select(ProfileEffectStyle effect) async {
    setState(() => _saving = true);
    try {
      await ref.read(profileEffectProvider.notifier).select(effect);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('特效未保存，请重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(profileEffectProvider);
    final avatarUrl = ref.watch(
      platformAccountProvider.select((value) => value.value?.avatarUrl ?? ''),
    );
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('个人页特效', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.surfaceContainerHigh,
                  colors.surfaceContainerLow,
                ],
              ),
            ),
            child: SizedBox(
              key: const ValueKey('profile-effect-preview'),
              height: 144,
              child: VipProfileEffects(
                enabled: true,
                inGallery: true,
                avatarKey: _avatar,
                child: Center(
                  child: VipEffectAnchor(
                    handle: _avatar,
                    child: PlatformAvatar(url: avatarUrl, size: 66),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final effect in ProfileEffectStyle.values)
              ChoiceChip(
                key: ValueKey('profile-effect-${effect.name}'),
                label: Text(effect.label),
                labelStyle: theme.textTheme.labelLarge,
                selected: selected == effect,
                onSelected: _saving
                    ? null
                    : (_) {
                        if (selected != effect) _select(effect);
                      },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          selected == ProfileEffectStyle.rhythm
              ? '播放音乐时可预览律动和飘落音符'
              : selected.description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
