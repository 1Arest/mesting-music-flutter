import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/beta_text_editing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_facing_error.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../auth/auth_providers.dart';
import '../../social/domain/social_models.dart';
import '../../social/social_providers.dart';
import '../../themes/music_theme_tokens.dart';
import '../profile_background_controller.dart';
import 'avatar_preview_page.dart';
import 'profile_background_visual.dart';

const liquidGlassProfileEditSurfaceKey = ValueKey<String>(
  'liquid-glass-profile-edit-surface',
);
const profileEditNicknameFieldSurfaceKey = ValueKey<String>(
  'profile-edit-nickname-field-surface',
);
const profileEditBioFieldSurfaceKey = ValueKey<String>(
  'profile-edit-bio-field-surface',
);

class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nicknameController;
  late final TextEditingController _bioController;
  int? _age;
  String _zodiac = '';
  int? _initialAge;
  String _initialZodiac = '';
  bool _saving = false;
  bool _detailsChanged = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _nicknameController = TextEditingController(text: user?.nickname ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
    _age = user?.age;
    _zodiac = user?.zodiac ?? '';
    _initialAge = _age;
    _initialZodiac = _zodiac;
    if (user != null) {
      Future<void>.microtask(() => _loadSocialDetails(user.uid));
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.value?.user;
    final topInset = MediaQuery.paddingOf(context).top;
    final scheme = Theme.of(context).colorScheme;
    final profileBackground = ref.watch(profileBackgroundProvider);
    if (user == null && !auth.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/profile');
      });
    }
    return LiquidGlassSurface(
      key: liquidGlassProfileEditSurfaceKey,
      borderRadius: BorderRadius.zero,
      child: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          physics: const ArtworkFrontierPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: BetaContentInsets.musicPaddingOf(
            context,
            EdgeInsets.fromLTRB(16, topInset + 12, 16, 170),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      '编辑个人资料',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  '完善公开资料，让朋友更了解你',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 22),
                GlassCard(
                  key: const ValueKey('profile-edit-avatar-card'),
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 21),
                  child: Column(
                    children: [
                      Semantics(
                        button: true,
                        label: '预览和管理头像',
                        child: GestureDetector(
                          key: const ValueKey(
                            'profile-edit-avatar-preview-entry',
                          ),
                          onTap: () => context.push('/profile/avatar'),
                          child: Hero(
                            tag: profileAvatarHeroTag,
                            createRectTween: (begin, end) =>
                                MaterialRectCenterArcTween(
                                  begin: begin,
                                  end: end,
                                ),
                            transitionOnUserGestures: true,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  key: const ValueKey('profile-edit-avatar'),
                                  width: 112,
                                  height: 112,
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [scheme.primary, scheme.tertiary],
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: scheme.primary.withValues(
                                          alpha: .24,
                                        ),
                                        blurRadius: 26,
                                        offset: const Offset(0, 12),
                                      ),
                                    ],
                                  ),
                                  child: user?.avatarUrl != null
                                      ? ArtworkImage(
                                          uri: user!.avatarUrl!,
                                          width: 112,
                                          height: 112,
                                          fit: BoxFit.cover,
                                          retryOnNetworkError: true,
                                        )
                                      : const Icon(
                                          Icons.person_rounded,
                                          size: 58,
                                          color: Colors.white,
                                        ),
                                ),
                                Positioned(
                                  right: -4,
                                  bottom: -4,
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: scheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: scheme.surface,
                                        width: 3,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.open_in_full_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '点击预览头像',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  padding: EdgeInsets.zero,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: const ValueKey('profile-edit-background-entry'),
                      onTap: () => context.push('/profile/background'),
                      borderRadius: BorderRadius.circular(26),
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 74,
                              height: 54,
                              child: ProfileBackgroundVisual(
                                key: const ValueKey(
                                  'profile-edit-background-preview',
                                ),
                                background: profileBackground,
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            const SizedBox(width: 13),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '个人主页背景',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '预览、更换背景图片或选择背景风格',
                                    style: TextStyle(fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const _EditSectionTitle(
                  title: '基本资料',
                  subtitle: '昵称和个人简介会展示在你的主页',
                ),
                const SizedBox(height: 9),
                GlassCard(
                  key: const ValueKey('profile-edit-basic-card'),
                  padding: const EdgeInsets.fromLTRB(14, 15, 14, 9),
                  child: Column(
                    children: [
                      _ProfileTextFieldSurface(
                        surfaceKey: profileEditNicknameFieldSurfaceKey,
                        child: TextFormField(
                          contextMenuBuilder: buildBetaEditingMenu,
                          selectionControls: mestingTextSelectionControls,
                          cursorRadius: const Radius.circular(1),
                          controller: _nicknameController,
                          maxLength: 24,
                          decoration: const InputDecoration(
                            labelText: '昵称',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (value) => (value ?? '').trim().length < 2
                              ? '昵称至少需要 2 个字符'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _ProfileTextFieldSurface(
                        surfaceKey: profileEditBioFieldSurfaceKey,
                        child: TextFormField(
                          contextMenuBuilder: buildBetaEditingMenu,
                          selectionControls: mestingTextSelectionControls,
                          cursorRadius: const Radius.circular(1),
                          controller: _bioController,
                          maxLength: 120,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: '个人简介',
                            alignLabelWithHint: true,
                            prefixIcon: Icon(Icons.notes_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const _EditSectionTitle(
                  title: '更多资料',
                  subtitle: '选填 · 设置后会展示在好友主页',
                ),
                const SizedBox(height: 9),
                GlassCard(
                  key: const ValueKey('profile-edit-details-card'),
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _ProfileValueRow(
                        key: const ValueKey('profile-edit-age'),
                        icon: Icons.cake_outlined,
                        label: '年龄',
                        value: _age == null ? '未设置' : '$_age 岁',
                        onTap: _chooseAge,
                      ),
                      const Divider(height: 1, indent: 58),
                      _ProfileValueRow(
                        key: const ValueKey('profile-edit-zodiac'),
                        icon: Icons.auto_awesome_outlined,
                        label: '星座',
                        value: _zodiac.isEmpty ? '未设置' : _zodiac,
                        onTap: _chooseZodiac,
                      ),
                    ],
                  ),
                ),
                if (auth.hasError) ...[
                  const SizedBox(height: 10),
                  Text(
                    userFacingErrorMessage(
                      auth.error,
                      fallback: '个人资料加载失败，请稍后重试',
                    ),
                    style: const TextStyle(
                      color: Color(0xFFC24A34),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: auth.isLoading || _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: auth.isLoading || _saving
                        ? const SizedBox.square(
                            dimension: 21,
                            child: MusicActivityIndicator(
                              independent: true,
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '保存资料',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadSocialDetails(String uid) async {
    try {
      final profile = await ref.read(socialUserProvider(uid).future);
      if (!mounted || _detailsChanged) return;
      setState(() {
        _age = profile.age;
        _zodiac = profile.zodiac;
        _initialAge = profile.age;
        _initialZodiac = profile.zodiac;
      });
    } on Object {
      // The locally restored values remain editable when social sync is
      // temporarily unavailable.
    }
  }

  Future<void> _chooseAge() async {
    final selection = await showLiquidGlassBottomSheet<_AgeSelection>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (_) => _AgePickerSheet(initialAge: _age),
    );
    if (selection == null || !mounted) return;
    setState(() {
      _age = selection.age;
      _detailsChanged = _age != _initialAge || _zodiac != _initialZodiac;
    });
  }

  Future<void> _chooseZodiac() async {
    final zodiac = await showLiquidGlassBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ZodiacPickerSheet(selected: _zodiac),
    );
    if (zodiac == null || !mounted) return;
    setState(() {
      _zodiac = zodiac;
      _detailsChanged = _age != _initialAge || _zodiac != _initialZodiac;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final controller = ref.read(authControllerProvider.notifier);
    final success = await controller.updateProfile(
      nickname: _nicknameController.text.trim(),
      bio: _bioController.text.trim(),
      age: _age,
      zodiac: _zodiac,
    );
    if (!mounted) return;
    if (!success) {
      setState(() => _saving = false);
      showMusicNotice(
        context,
        icon: Icons.error_outline_rounded,
        title: '保存失败',
        message: userFacingErrorMessage(
          controller.lastError,
          fallback: '暂时无法更新个人资料，请稍后重试',
        ),
      );
      return;
    }
    if (_detailsChanged) {
      try {
        await ref
            .read(socialRepositoryProvider)
            .updateProfileDetails(age: _age, zodiac: _zodiac);
        final uid = ref.read(currentUserProvider)?.uid;
        if (uid != null) ref.invalidate(socialUserProvider(uid));
        ref.invalidate(socialConnectionsProvider);
        ref.invalidate(socialUserSearchProvider);
      } on Object catch (error) {
        if (!mounted) return;
        setState(() => _saving = false);
        showMusicNotice(
          context,
          icon: Icons.sync_problem_rounded,
          title: '基本资料已保存',
          message: userFacingErrorMessage(
            error,
            fallback: '年龄和星座暂时未同步，请稍后再次保存',
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    showMusicNotice(
      context,
      icon: Icons.check_rounded,
      title: '资料已保存',
      message: '头像、昵称、简介和更多资料已更新',
    );
    context.pop();
  }
}

class _ProfileTextFieldSurface extends StatefulWidget {
  const _ProfileTextFieldSurface({
    required this.surfaceKey,
    required this.child,
  });

  final Key surfaceKey;
  final Widget child;

  @override
  State<_ProfileTextFieldSurface> createState() =>
      _ProfileTextFieldSurfaceState();
}

class _ProfileTextFieldSurfaceState extends State<_ProfileTextFieldSurface> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.musicThemeTokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Focus(
      onFocusChange: (focused) {
        if (_focused != focused) setState(() => _focused = focused);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            bottom: 19,
            child: IgnorePointer(
              child: AnimatedContainer(
                key: widget.surfaceKey,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: _focused
                          ? scheme.primary.withValues(alpha: dark ? .24 : .16)
                          : Colors.black.withValues(alpha: dark ? .3 : .105),
                      blurRadius: _focused ? 18 : 16,
                      spreadRadius: _focused ? 0 : -1,
                      offset: Offset(0, _focused ? 6 : 7),
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: dark ? .055 : .7),
                      blurRadius: 3,
                      offset: const Offset(-1, -1),
                    ),
                  ],
                  border: Border.all(
                    color: _focused
                        ? scheme.primary.withValues(alpha: dark ? .52 : .36)
                        : tokens.borderStrong.withValues(
                            alpha: dark ? .38 : .72,
                          ),
                    width: _focused ? 1.1 : .8,
                  ),
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _EditSectionTitle extends StatelessWidget {
  const _EditSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              subtitle,
              textAlign: TextAlign.right,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileValueRow extends StatelessWidget {
  const _ProfileValueRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(17, 16, 13, 16),
        child: Row(
          children: [
            Icon(icon, size: 22, color: scheme.primary),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: value == '未设置'
                    ? scheme.onSurfaceVariant.withValues(alpha: .72)
                    : scheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: scheme.onSurfaceVariant.withValues(alpha: .65),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgeSelection {
  const _AgeSelection(this.age);

  final int? age;
}

class _AgePickerSheet extends StatefulWidget {
  const _AgePickerSheet({required this.initialAge});

  final int? initialAge;

  @override
  State<_AgePickerSheet> createState() => _AgePickerSheetState();
}

class _AgePickerSheetState extends State<_AgePickerSheet> {
  late int _age;

  @override
  void initState() {
    super.initState();
    _age = widget.initialAge ?? 18;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 18, 22, bottom + 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '设置年龄',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Text(
              '设置后会展示在好友主页，也可以随时清除',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  key: const ValueKey('profile-age-decrease'),
                  tooltip: '减少一岁',
                  onPressed: _age <= 1 ? null : () => setState(() => _age -= 1),
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 132,
                  child: Text(
                    '$_age 岁',
                    key: const ValueKey('profile-age-value'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 31,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  key: const ValueKey('profile-age-increase'),
                  tooltip: '增加一岁',
                  onPressed: _age >= 120
                      ? null
                      : () => setState(() => _age += 1),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            Slider(
              key: const ValueKey('profile-age-slider'),
              value: _age.toDouble(),
              min: 1,
              max: 120,
              divisions: 119,
              label: '$_age 岁',
              onChanged: (value) => setState(() => _age = value.round()),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('profile-age-clear'),
                    onPressed: () =>
                        Navigator.pop(context, const _AgeSelection(null)),
                    child: const Text('暂不设置'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('profile-age-confirm'),
                    onPressed: () =>
                        Navigator.pop(context, _AgeSelection(_age)),
                    child: const Text('完成'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ZodiacPickerSheet extends StatelessWidget {
  const _ZodiacPickerSheet({required this.selected});

  final String selected;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(18, 18, 18, bottom + 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '选择星座',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Text(
              '选择后会展示在好友主页',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
            const SizedBox(height: 18),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: socialZodiacSigns.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.35,
              ),
              itemBuilder: (context, index) {
                final zodiac = socialZodiacSigns[index];
                final active = zodiac == selected;
                return InkWell(
                  key: ValueKey('profile-zodiac-$zodiac'),
                  onTap: () => Navigator.pop(context, zodiac),
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: active
                          ? scheme.primary.withValues(alpha: .14)
                          : scheme.surfaceContainerHighest.withValues(
                              alpha: .62,
                            ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: active
                            ? scheme.primary.withValues(alpha: .55)
                            : scheme.outlineVariant.withValues(alpha: .45),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        zodiac,
                        style: TextStyle(
                          color: active ? scheme.primary : scheme.onSurface,
                          fontWeight: active
                              ? FontWeight.w900
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const ValueKey('profile-zodiac-clear'),
                onPressed: () => Navigator.pop(context, ''),
                child: const Text('暂不设置'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
