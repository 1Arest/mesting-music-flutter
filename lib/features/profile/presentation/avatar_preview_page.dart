import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/user_facing_error.dart';
import '../../../core/platform/avatar_media_bridge.dart';
import '../../../core/security/avatar_image_validator.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../auth/auth_providers.dart';

const profileAvatarHeroTag = 'profile-avatar-preview';

class AvatarPreviewPage extends ConsumerStatefulWidget {
  const AvatarPreviewPage({super.key});

  @override
  ConsumerState<AvatarPreviewPage> createState() => _AvatarPreviewPageState();
}

class _AvatarPreviewPageState extends ConsumerState<AvatarPreviewPage> {
  bool _saving = false;
  bool _changing = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final avatarUrl = user?.avatarUrl?.trim() ?? '';
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return ColoredBox(
      color: Colors.black,
      child: Column(
        children: [
          SizedBox(height: topInset + 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: '关闭头像预览',
                  child: InkWell(
                    key: const ValueKey('avatar-preview-close'),
                    onTap: () => context.pop(),
                    borderRadius: BorderRadius.circular(18),
                    child: const SizedBox(
                      width: 52,
                      height: 52,
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 31,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                const Text(
                  '当前头像',
                  style: TextStyle(
                    color: Color(0xB8FFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 52),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final previewHeight = constraints.maxHeight.clamp(240.0, 620.0);
                return Center(
                  child: Hero(
                    tag: profileAvatarHeroTag,
                    createRectTween: (begin, end) =>
                        MaterialRectCenterArcTween(begin: begin, end: end),
                    transitionOnUserGestures: true,
                    child: Material(
                      color: Colors.black,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        height: previewHeight,
                        child: avatarUrl.isEmpty
                            ? const _EmptyAvatarPreview()
                            : InteractiveViewer(
                                minScale: 1,
                                maxScale: 4,
                                boundaryMargin: const EdgeInsets.all(36),
                                child: Center(
                                  child: ArtworkImage(
                                    key: ValueKey(avatarUrl),
                                    uri: avatarUrl,
                                    width: constraints.maxWidth,
                                    height: previewHeight,
                                    decodeWidth: constraints.maxWidth,
                                    fit: BoxFit.contain,
                                    retryOnNetworkError: true,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, bottomInset + 24),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _AvatarActionButton(
                        key: const ValueKey('save-current-avatar'),
                        icon: Icons.download_rounded,
                        label: _saving ? '正在保存' : '保存头像',
                        enabled: avatarUrl.isNotEmpty && !_saving && !_changing,
                        onTap: () => _saveAvatar(avatarUrl),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _AvatarActionButton(
                        key: const ValueKey('change-current-avatar'),
                        icon: Icons.photo_library_outlined,
                        label: _changing ? '正在更新' : '更换头像',
                        enabled: !_saving && !_changing && user != null,
                        onTap: _changeAvatar,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  avatarUrl.isEmpty
                      ? '当前尚未设置头像，可从相册选择一张'
                      : '可双指缩放 · 保存到“图片 / Mesting Music”',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF77727A),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeAvatar() async {
    final user = ref.read(currentUserProvider);
    if (user == null || _changing) return;
    final selected = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 88,
    );
    if (selected == null || !mounted) return;

    try {
      await validateAvatarImage(selected.path);
    } on AvatarValidationException catch (error) {
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: Icons.image_not_supported_rounded,
        title: '头像不可用',
        message: error.message,
      );
      return;
    }

    setState(() => _changing = true);
    final controller = ref.read(authControllerProvider.notifier);
    final success = await controller.updateProfile(
      nickname: user.nickname,
      bio: user.bio,
      avatarPath: selected.path,
    );
    if (!mounted) return;
    setState(() => _changing = false);
    showMusicNotice(
      context,
      icon: success ? Icons.check_rounded : Icons.error_outline_rounded,
      title: success ? '头像已更新' : '头像更新失败',
      message: success
          ? '新的头像已同步到个人资料'
          : userFacingErrorMessage(
              controller.lastError,
              fallback: '头像更新失败，请稍后重试',
            ),
    );
  }

  Future<void> _saveAvatar(String avatarUrl) async {
    if (_saving || avatarUrl.isEmpty) return;
    setState(() => _saving = true);
    try {
      final image = await AvatarMediaBridge.load(avatarUrl);
      await AvatarMediaBridge.saveToGallery(image);
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: Icons.download_done_rounded,
        title: '头像已保存',
        message: '可以在系统相册的 Mesting Music 中查看',
      );
    } on AvatarMediaException catch (error) {
      if (!mounted) return;
      _showSaveError(error.message);
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showSaveError(error.message ?? '系统相册暂时不可用，请稍后重试');
    } on MissingPluginException {
      if (!mounted) return;
      _showSaveError('当前设备暂不支持保存头像');
    } on Object {
      if (!mounted) return;
      _showSaveError('头像保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSaveError(String message) {
    showMusicNotice(
      context,
      icon: Icons.error_outline_rounded,
      title: '保存失败',
      message: message,
    );
  }
}

class _AvatarActionButton extends StatelessWidget {
  const _AvatarActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : .42,
      child: Material(
        color: const Color(0xFF171719),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF27272B)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 62,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 23),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
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

class _EmptyAvatarPreview extends StatelessWidget {
  const _EmptyAvatarPreview();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 180,
        height: 180,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFF8296F2), Color(0xFF3F9FB0)],
          ),
        ),
        child: const Icon(Icons.person_rounded, color: Colors.white, size: 96),
      ),
    );
  }
}
