import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_glass_scroll_body.dart';
import '../../../shared/widgets/beta_text_editing.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../shared/widgets/music_feature_page.dart';
import '../../../shared/widgets/music_notice.dart';
import '../domain/platform_session.dart';
import '../domain/platform_regions.dart';
import '../data/platform_profile_repository.dart';
import '../music_platform_providers.dart';
import '../platform_profile_provider.dart';
import 'platform_avatar.dart';
import 'platform_region_picker.dart';

/// One edit session belongs to the account present on entry. Account changes
/// invalidate the form rather than silently applying its draft to another user.
class PlatformProfileEditPage extends ConsumerStatefulWidget {
  const PlatformProfileEditPage({super.key});
  @override
  ConsumerState<PlatformProfileEditPage> createState() =>
      _PlatformProfileEditPageState();
}

class _PlatformProfileEditPageState
    extends ConsumerState<PlatformProfileEditPage> {
  late final PlatformSession? _owner;
  final _nickname = TextEditingController(),
      _signature = TextEditingController();
  PlatformProfileInfo? _initial;
  int? _sex;
  String? _birthday, _province, _city, _error;
  Uint8List? _pendingAvatar;
  bool _saving = false,
      _uploading = false,
      _allowExit = false,
      _askingDiscard = false;
  bool get _busy => _saving || _uploading;
  Map<String, Object?> get _changes => _initial == null
      ? {}
      : profileChanges(
          _initial!,
          nickname: _nickname.text,
          signature: _signature.text,
          sex: _sex,
          birthday: _birthday,
          province: _province,
          city: _city,
        );

  @override
  void initState() {
    super.initState();
    _owner = ref.read(platformAccountProvider).value;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _signature.dispose();
    super.dispose();
  }

  Future<void> _leave(bool didPop, Object? result) async {
    if (didPop || _askingDiscard || _busy) return;
    _askingDiscard = true;
    final discard = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('放弃本次修改？'),
        content: const Text('尚未保存的资料会被丢弃。已提交的头像不受影响。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    _askingDiscard = false;
    if (discard == true && mounted) {
      setState(() => _allowExit = true);
      Navigator.pop(context);
    }
  }

  Future<void> _save() async {
    if (_busy || _owner == null || _changes.isEmpty) return;
    if (_nickname.text.trim().isEmpty) {
      setState(() => _error = '昵称不能为空');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(platformProfileRepositoryProvider);
      await repository.save(_owner, _changes);
      // Server acceptance and local metadata refresh are separate outcomes.
      // A failed read-back must not encourage duplicate account writes.
      try {
        final fresh = await repository.fetch(_owner);
        await ref
            .read(platformAccountProvider.notifier)
            .updateProfileMetadata(
              _owner,
              nickname: fresh.nickname,
              avatarUrl: fresh.avatarUrl,
            );
      } on Object {
        /* The submitted profile can be refreshed on the next visit. */
      }
      ref.invalidate(platformProfileProvider);
      if (!mounted) return;
      setState(() {
        _allowExit = true;
        _saving = false;
      });
      showMusicNotice(
        context,
        title: '资料已提交',
        message: '',
        icon: CupertinoIcons.check_mark,
      );
      Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _avatar() async {
    if (_busy || _owner == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (image == null || !mounted) return;
      if (await image.length() > PlatformProfileRepository.maximumAvatarBytes) {
        throw StateError('请选择小于 2 MB 的头像图片');
      }
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      final confirmed = await showLiquidGlassBottomSheet<bool>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '更换头像',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),
              ClipOval(
                child: Image.memory(
                  bytes,
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 24),
              BetaGlassButton(
                blue: true,
                onPressed: () => Navigator.pop(context, true),
                child: const Text('使用这张头像'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      await ref
          .read(platformProfileRepositoryProvider)
          .uploadAvatar(_owner, bytes);
      ref.invalidate(platformProfileProvider);
      if (!mounted) return;
      setState(() => _pendingAvatar = bytes);
      showMusicNotice(
        context,
        title: '头像已提交',
        message: '审核后生效',
        icon: CupertinoIcons.check_mark,
      );
    } on Object {
      if (mounted) setState(() => _error = '头像未能提交，请检查图片格式和网络后重试');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickSex() async {
    final value = await showCupertinoModalPopup<int>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('性别'),
        actions: [
          for (final choice in const [(0, '女'), (1, '男'), (2, '保密')])
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, choice.$1),
              child: Text(choice.$2),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
    if (value != null && mounted) setState(() => _sex = value);
  }

  Future<void> _pickBirthday() async {
    var selected = DateTime.tryParse(_birthday ?? '') ?? DateTime(2000);
    final today = DateTime.now();
    if (selected.isAfter(today)) selected = today;
    final value = await showLiquidGlassBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const Expanded(
                  child: Text(
                    '生日',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.pop(
                    context,
                    PlatformProfileInfo.normalizeBirthday(
                      selected.toIso8601String(),
                    ),
                  ),
                  child: const Text('完成'),
                ),
              ],
            ),
            SizedBox(
              height: 240,
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: selected,
                minimumDate: DateTime(1900),
                maximumDate: today,
                onDateTimeChanged: (value) => selected = value,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('清除生日'),
            ),
          ],
        ),
      ),
    );
    if (value != null && mounted) setState(() => _birthday = value);
  }

  Future<void> _pickRegion() async {
    try {
      final regions = await ref.read(musicRegionsProvider.future);
      if (!mounted) return;
      final selected = await showPlatformRegionPicker(
        context,
        regions,
        province: _province,
        city: _city,
      );
      if (selected != null && mounted) {
        setState(() {
          _province = selected.province;
          _city = selected.city;
        });
      }
    } on Object {
      if (mounted) setState(() => _error = '地区列表加载失败，请重试');
    }
  }

  String _regionLabel(List<MusicRegion>? regions) {
    var provinceLabel = _province ?? '', cityLabel = _city ?? '';
    if (regions != null) {
      final selected = resolveMusicRegion(
        regions,
        province: _province,
        city: _city,
      );
      final region = selected.province;
      if (region != null) {
        provinceLabel = region.name;
        final city = selected.city;
        if (city != null) cityLabel = city.name;
      }
    }
    return [
      provinceLabel,
      if (cityLabel != provinceLabel) cityLabel,
    ].where((s) => s.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(platformAccountProvider).value;
    final valid =
        _owner != null &&
        current?.ownerId == _owner.ownerId &&
        current?.token == _owner.token;
    final details = valid
        ? ref.watch(platformEditableProfileProvider(_owner))
        : null;
    final scheme = Theme.of(context).colorScheme;
    final regions = ref.watch(musicRegionsProvider).value;
    return PopScope<Object?>(
      canPop: _allowExit || (!_busy && _changes.isEmpty),
      onPopInvokedWithResult: _leave,
      child: MusicFeaturePage(
        title: '编辑个人资料',
        child: !valid
            ? const MusicFeatureMessage(message: '账号已变化，请返回后重新进入资料编辑。')
            : details!.when(
                loading: () => const Center(child: BetaActivityIndicator()),
                error: (_, _) => MusicFeatureMessage(
                  message: '暂时无法读取酷狗资料。请重试，避免覆盖尚未读取的字段。',
                  onRetry: () =>
                      ref.invalidate(platformEditableProfileProvider(_owner)),
                ),
                data: (profile) {
                  if (_initial == null) {
                    _initial = profile;
                    _nickname.text = profile.nickname;
                    _signature.text = profile.signature ?? '';
                    _sex = profile.sex;
                    _birthday = profile.birthday;
                    _province = profile.province;
                    _city = profile.city;
                  }
                  return BetaGlassScrollBody(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 40),
                    children: [
                      Center(
                        child: Semantics(
                          button: true,
                          label: '更换酷狗头像',
                          child: CupertinoButton(
                            key: const ValueKey('platform-edit-avatar'),
                            padding: const EdgeInsets.all(8),
                            onPressed: _busy ? null : _avatar,
                            child: Column(
                              children: [
                                if (_pendingAvatar != null)
                                  ClipOval(
                                    child: Image.memory(
                                      _pendingAvatar!,
                                      width: 96,
                                      height: 96,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                else
                                  PlatformAvatar(
                                    url: profile.avatarUrl,
                                    size: 96,
                                  ),
                                const SizedBox(height: 12),
                                Text(
                                  _uploading
                                      ? '正在提交头像'
                                      : _pendingAvatar != null
                                      ? '头像已提交，等待审核'
                                      : '更换头像',
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      _label('昵称'),
                      BetaGlassField(
                        child: TextField(
                          key: const ValueKey('platform-edit-nickname'),
                          controller: _nickname,
                          enabled: !_busy,
                          maxLength: 30,
                          contextMenuBuilder: buildBetaEditingMenu,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(hintText: '输入昵称'),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          children: [
                            _row('性别', switch (_sex) {
                              0 => '女',
                              1 => '男',
                              2 => '保密',
                              _ => '未设置',
                            }, _pickSex),
                            const Divider(height: 1, indent: 18, endIndent: 18),
                            _row(
                              '生日',
                              _birthday?.isNotEmpty == true
                                  ? _birthday!
                                  : '未设置',
                              _pickBirthday,
                            ),
                            const Divider(height: 1, indent: 18, endIndent: 18),
                            _row('地区', _regionLabel(regions), _pickRegion),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      _label('个性签名'),
                      BetaGlassField(
                        child: TextField(
                          key: const ValueKey('platform-edit-signature'),
                          controller: _signature,
                          enabled: !_busy,
                          minLines: 3,
                          maxLines: 5,
                          maxLength: 280,
                          contextMenuBuilder: buildBetaEditingMenu,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: '写一点关于自己的话',
                          ),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: Text(
                            _error!,
                            style: TextStyle(color: scheme.error, height: 1.5),
                          ),
                        ),
                      const SizedBox(height: 28),
                      BetaGlassButton(
                        key: const ValueKey('platform-edit-save'),
                        blue: true,
                        loading: _saving,
                        onPressed: _busy || _changes.isEmpty ? null : _save,
                        child: const Text('保存资料'),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '修改将同步到当前酷狗账号。头像提交后需由平台审核。',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(left: 8, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );
  Widget _row(String label, String value, VoidCallback onTap) =>
      CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        onPressed: _busy ? null : onTap,
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                value.isEmpty ? '未设置' : value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      );
}
