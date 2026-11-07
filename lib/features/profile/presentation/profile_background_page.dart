import 'package:flutter/material.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../shared/widgets/music_notice.dart';
import '../profile_background_controller.dart';
import 'profile_background_visual.dart';

class ProfileBackgroundPage extends ConsumerStatefulWidget {
  const ProfileBackgroundPage({super.key});

  @override
  ConsumerState<ProfileBackgroundPage> createState() =>
      _ProfileBackgroundPageState();
}

class _ProfileBackgroundPageState extends ConsumerState<ProfileBackgroundPage> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final background = ref.watch(profileBackgroundProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: '关闭背景预览',
                    child: IconButton(
                      key: const ValueKey('profile-background-close'),
                      onPressed: _saving ? null : () => context.pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 31,
                      ),
                      tooltip: '关闭',
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '个人主页背景',
                    style: TextStyle(
                      color: Color(0xB8FFFFFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<_BackgroundMenuAction>(
                    key: const ValueKey('profile-background-more'),
                    enabled: !_saving,
                    color: const Color(0xFF211F22),
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      color: Colors.white,
                    ),
                    onSelected: (value) {
                      if (value == _BackgroundMenuAction.restore) {
                        _restoreDefault();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _BackgroundMenuAction.restore,
                        child: Text(
                          '恢复默认背景',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final previewHeight = (constraints.maxWidth * 1.05).clamp(
                      280.0,
                      constraints.maxHeight * .76,
                    );
                    return SizedBox(
                      width: constraints.maxWidth,
                      height: previewHeight,
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: background.isImage ? 4 : 1,
                        boundaryMargin: const EdgeInsets.all(40),
                        child: ProfileBackgroundVisual(
                          background: background,
                          fit: background.isImage
                              ? BoxFit.contain
                              : BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, bottomInset + 26),
              child: Column(
                children: [
                  if (_saving) ...[
                    const Center(
                      child: MusicActivityIndicator(independent: true),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: _BackgroundActionButton(
                          key: const ValueKey('change-profile-background'),
                          icon: Icons.photo_library_outlined,
                          label: '更换背景',
                          enabled: !_saving,
                          onTap: _pickBackground,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _BackgroundActionButton(
                          key: const ValueKey('create-profile-background'),
                          icon: Icons.auto_awesome_rounded,
                          label: '风格创作',
                          enabled: !_saving,
                          onTap: _showStyleCreator,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '背景图片与风格会保存到当前账号，清除数据后重新登录仍可恢复',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF777277),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBackground() async {
    if (_saving) return;
    final selected = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2560,
      imageQuality: 92,
    );
    if (selected == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(profileBackgroundProvider.notifier)
          .setImage(selected.path);
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: Icons.check_rounded,
        title: '背景已更新',
        message: '新的背景已应用到个人主页',
      );
    } on ProfileBackgroundException catch (error) {
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: Icons.image_not_supported_rounded,
        title: '背景更新失败',
        message: error.message,
      );
    } on Object {
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: Icons.error_outline_rounded,
        title: '背景更新失败',
        message: '背景图片处理失败，请重新选择或稍后重试',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showStyleCreator() async {
    final selected = await showLiquidGlassBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showTopHighlight: false,
      builder: (context) => _BackgroundStyleSheet(
        selectedId: ref.read(profileBackgroundProvider).presetId,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(profileBackgroundProvider.notifier).setPreset(selected);
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: Icons.auto_awesome_rounded,
        title: '背景风格已应用',
        message: '${profileBackgroundPresetById(selected).name}已保存到当前账号',
      );
    } on ProfileBackgroundException catch (error) {
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: Icons.error_outline_rounded,
        title: '背景设置失败',
        message: error.message,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restoreDefault() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(profileBackgroundProvider.notifier).clear();
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: Icons.restart_alt_rounded,
        title: '已恢复默认背景',
        message: '个人主页已恢复为当前主题的默认样式',
      );
    } on ProfileBackgroundException catch (error) {
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: Icons.error_outline_rounded,
        title: '恢复失败',
        message: error.message,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

enum _BackgroundMenuAction { restore }

class _BackgroundActionButton extends StatelessWidget {
  const _BackgroundActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: const Color(0xFF1D1D1F),
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(30),
          child: SizedBox(
            height: 58,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 21),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BackgroundStyleSheet extends StatelessWidget {
  const _BackgroundStyleSheet({required this.selectedId});

  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF181619),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(18, 12, 18, bottomInset + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0x4DFFFFFF),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '风格创作',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '选择一套本地生成的主页背景，不会上传任何照片。',
              style: TextStyle(
                color: Color(0xFF999399),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: profileBackgroundPresets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.35,
              ),
              itemBuilder: (context, index) {
                final preset = profileBackgroundPresets[index];
                final selected = preset.id == selectedId;
                return Semantics(
                  button: true,
                  selected: selected,
                  label: '${preset.name}，${preset.description}',
                  child: InkWell(
                    key: ValueKey('profile-background-preset-${preset.id}'),
                    onTap: () => context.pop(preset.id),
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ProfileBackgroundVisual(
                          background: ProfileBackgroundState(
                            accountId: 'preview',
                            kind: ProfileBackgroundKind.preset,
                            value: preset.id,
                          ),
                          dim: true,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        Positioned(
                          left: 14,
                          right: 12,
                          bottom: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                preset.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                preset.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xC7FFFFFF),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (selected)
                          const Positioned(
                            right: 10,
                            top: 10,
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
