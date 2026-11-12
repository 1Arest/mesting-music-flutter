import 'style_option_grid.dart';
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
                    child: PlatformAvatar(
                      url: avatarUrl,
                      size: 66,
                      personal: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        StyleOptionGrid(
          values: ProfileEffectStyle.values.map((e) => e.name).toList(),
          labels: ProfileEffectStyle.values.map((e) => e.label).toList(),
          selected: selected.name,
          keyPrefix: 'profile-effect',
          onSelected: _saving
              ? null
              : (value) => _select(ProfileEffectStyle.values.byName(value)),
          preview: (value) =>
              _ProfileEffectThumbnail(ProfileEffectStyle.values.byName(value)),
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

/// A still from the production painter; the larger selected preview above uses
/// live playback. Keeping these catalogue samples static avoids five tickers.
class _ProfileEffectThumbnail extends StatelessWidget {
  const _ProfileEffectThumbnail(this.effect);
  final ProfileEffectStyle effect;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final center = Offset(c.maxWidth / 2, c.maxHeight / 2);
      const still = AlwaysStoppedAnimation<double>(.24);
      return CustomPaint(
        painter: VipProfilePainter(
          style: effect,
          animation: still,
          geometryChanges: still,
          avatarRect: () => Rect.fromCircle(center: center, radius: 17),
          reduced: false,
        ),
        child: const Center(
          child: CircleAvatar(radius: 17, child: Icon(Icons.person, size: 20)),
        ),
      );
    },
  );
}
