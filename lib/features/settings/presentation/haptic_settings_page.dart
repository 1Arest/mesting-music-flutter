import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_glass_scroll_body.dart';
import '../../../shared/widgets/music_notice.dart';

/// A small grouped settings surface. It edits preferences; the platform bridge
/// owns capability checks, system opt-outs and tactile rendering separately.
class HapticSettingsPage extends ConsumerWidget {
  const HapticSettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(hapticPreferencesProvider);
    final controller = ref.read(hapticPreferencesProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('震动与触感')),
      body: SafeArea(
        top: false,
        child: BetaGlassScrollBody(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.hand_draw,
                    color: Color(0xFF007AFF),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      '应用触感',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  CupertinoSwitch(
                    key: const ValueKey('haptics-enabled'),
                    value: settings.enabled,
                    activeTrackColor: const Color(0xFF007AFF),
                    onChanged: (value) async {
                      await controller.setEnabled(value);
                      if (context.mounted && value) {
                        appHaptic(context, AppHapticEvent.selection);
                      }
                    },
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 14, 8, 30),
              child: Text('在切歌、菜单和确认操作等关键时刻提供短促反馈。'),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 12),
              child: Text(
                '反馈强度',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IgnorePointer(
              ignoring: !settings.enabled,
              child: Opacity(
                opacity: settings.enabled ? 1 : .5,
                child: CupertinoSlidingSegmentedControl<HapticStrength>(
                  groupValue: settings.strength,
                  children: {
                    for (final strength in HapticStrength.values)
                      strength: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 18,
                        ),
                        child: Text(strength.label),
                      ),
                  },
                  onValueChanged: (value) async {
                    if (value == null) return;
                    await controller.setStrength(value);
                    await ref
                        .read(appHapticsProvider)
                        .perform(AppHapticEvent.impact, preview: true);
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            BetaGlassButton(
              key: const ValueKey('haptics-preview'),
              blue: true,
              hapticFeedback: false,
              onPressed: !settings.enabled
                  ? null
                  : () async {
                      final played = await ref
                          .read(appHapticsProvider)
                          .perform(AppHapticEvent.impact, preview: true);
                      if (!played && context.mounted) {
                        showMusicNotice(
                          context,
                          icon: Icons.info_outline_rounded,
                          title: '触感暂不可用',
                          message: '请检查系统触感设置及设备支持情况',
                        );
                      }
                    },
              child: const Text('体验触感'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 0),
              child: Text(
                '遵循系统触感设置。实际效果取决于设备的震动马达。',
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
