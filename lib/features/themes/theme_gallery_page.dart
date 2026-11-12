import '../../shared/widgets/artwork_scroll_frontier.dart';
import '../../shared/widgets/beta_content_insets.dart';
import '../../shared/widgets/music_activity_indicator.dart';
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/music_notice.dart';
import '../../shared/widgets/beta_glass_action.dart';
import '../../shared/widgets/liquid_glass_sheet.dart';
import '../../core/platform/distribution_channel.dart';
import '../player/presentation/player_visual_stages.dart';
import '../player/presentation/vinyl_disc.dart';
import '../player/player_visual_style.dart';
import 'app_brand_style.dart';
import 'beta_appearance.dart';
import 'custom_background_controller.dart';
import 'music_theme_preset.dart';
import 'progress_outfit_picker.dart';
import 'theme_controller.dart';
import 'music_theme_tokens.dart';
import 'startup_style_picker.dart';
import 'music_typography.dart';

export 'progress_decoration_picker.dart' show ProgressDecorationPicker;

// This shared gallery keeps the formal channel's original control tint.
Color _galleryActionTint(BuildContext context) => DistributionChannel.isBeta
    ? BetaAppearance.accent(Theme.of(context).brightness)
    : BetaAppearance.artworkCoral;

Future<void>? _dressUpAssetWarmup;

Future<void> warmUpDressUpAssets(BuildContext context) {
  return _dressUpAssetWarmup ??= _warmUpDressUpAssets(context);
}

Future<void> _warmUpDressUpAssets(BuildContext context) async {
  final images = <ImageProvider<Object>>[
    const ResizeImage(
      AssetImage('assets/branding/mesting-mark-master.png'),
      width: 256,
    ),
    if (!DistributionChannel.isBeta)
      const ResizeImage(
        AssetImage('assets/branding/dress-morning-icon-v2.png'),
        width: 320,
      ),
    if (!DistributionChannel.isBeta)
      const ResizeImage(
        AssetImage('assets/branding/dress-midnight-icon-v2.png'),
        width: 320,
      ),
    const ResizeImage(
      AssetImage('assets/images/player/netease-style-tonearm.png'),
      width: 192,
    ),
    if (!DistributionChannel.isBeta)
      const AssetImage('assets/images/theme_playlists/shinchan/cover-01.jpg'),
  ];
  await Future.wait(
    images.map((image) async {
      try {
        await precacheImage(image, context);
      } on Object {
        // A missing optional preview must never block opening the drawer.
      }
    }),
  );
}

class DressUpAssetWarmup extends StatefulWidget {
  const DressUpAssetWarmup({super.key});

  @override
  State<DressUpAssetWarmup> createState() => _DressUpAssetWarmupState();
}

class _DressUpAssetWarmupState extends State<DressUpAssetWarmup> {
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(warmUpDressUpAssets(context));
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Future<void> showDressUpCenterSheet(BuildContext context) {
  unawaited(warmUpDressUpAssets(context));
  return showLiquidGlassBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: const Color(0x660E0C14),
    showTopHighlight: false,
    showShadow: false,
    showDecorativeGlow: false,
    blurSigma: 0,
    surfaceColorBuilder: (sheetContext) =>
        sheetContext.musicThemeTokens.glassStrong.withValues(alpha: 1),
    builder: (context) => const FractionallySizedBox(
      heightFactor: .965,
      child: _ThemeSettingsPanel(embeddedInGlassSheet: true),
    ),
  );
}

Future<void> showThemeSettingsSheet(BuildContext context) =>
    showDressUpCenterSheet(context);

class ThemeGalleryPage extends StatelessWidget {
  const ThemeGalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        // Beta reserves inside the scroll content so its surface can continue
        // painting behind the glass; Stable retains its existing frame.
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          DistributionChannel.isBeta ? 0 : 144,
        ),
        child: _ThemeSettingsPanel(onClose: context.pop),
      ),
    );
  }
}

class _ThemeSettingsPanel extends ConsumerStatefulWidget {
  const _ThemeSettingsPanel({this.onClose, this.embeddedInGlassSheet = false});

  final VoidCallback? onClose;
  final bool embeddedInGlassSheet;

  @override
  ConsumerState<_ThemeSettingsPanel> createState() =>
      _ThemeSettingsPanelState();
}

class _ThemeSettingsPanelState extends ConsumerState<_ThemeSettingsPanel> {
  MusicThemeIp? _activeIp;
  AppBrandStyle? _applyingBrandStyle;

  Future<void> _selectBrandStyle(AppBrandStyle style) async {
    if (_applyingBrandStyle != null) return;
    setState(() => _applyingBrandStyle = style);
    try {
      await ref.read(appBrandStyleProvider.notifier).select(style);
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: Icons.check_rounded,
        title: '${style.name}已保存',
        message: '下次启动生效',
      );
    } on Object {
      if (!mounted) return;
      showMusicNotice(
        context,
        icon: Icons.error_outline_rounded,
        title: '套装应用失败',
        message: '系统暂时无法保存品牌套装，请稍后重试',
      );
    } finally {
      if (mounted) setState(() => _applyingBrandStyle = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(musicThemeProvider);
    final effectiveTheme = ref.watch(effectiveMusicThemeProvider);
    final performance = ref.watch(themePerformanceProvider);
    final visual = ref.watch(themeVisualSettingsProvider);
    final brandStyle = ref.watch(appBrandStyleProvider);
    final playerStyle = ref.watch(playerVisualStyleProvider);
    final custom = ref.watch(customBackgroundProvider);
    final activeIp = _activeIp ?? selected.ip;
    final staticThemes = musicThemePresets
        .where((theme) => theme.ip == activeIp && !theme.isMotion)
        .toList(growable: false);
    final motionThemes = musicThemePresets
        .where((theme) => theme.ip == activeIp && theme.isMotion)
        .toList(growable: false);
    final tokens = context.musicThemeTokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    const panelRadius = BorderRadius.vertical(top: Radius.circular(30));

    final content = Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomScrollView(
              physics: const ArtworkFrontierPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    22,
                    20,
                    widget.embeddedInGlassSheet
                        ? 18
                        : BetaContentInsets.musicBottomOf(context, 18),
                  ),
                  sliver: SliverList.list(
                    children: [
                      const _PanelHeader(),
                      const SizedBox(height: 16),
                      if (DistributionChannel.isBeta) ...[
                        const _SettingsHeading(
                          title: '启动页',
                          description: '下次冷启动时展示；后台切回不会重播。',
                        ),
                        const SizedBox(height: 11),
                        const StartupStylePicker(),
                        const SizedBox(height: 24),
                      ],
                      if (!DistributionChannel.isBeta) ...[
                        const _SettingsHeading(
                          title: '品牌套装',
                          description: '成套切换桌面图标与下一次启动时的启动页。',
                        ),
                        const SizedBox(height: 11),
                        _BrandStylePicker(
                          selected: brandStyle,
                          applying: _applyingBrandStyle,
                          onSelected: _selectBrandStyle,
                        ),
                        const SizedBox(height: 24),
                      ],
                      const _SettingsHeading(
                        title: '播放器样式',
                        description: '切换全屏播放器的布局与控制质感，播放状态不会中断。',
                      ),
                      const SizedBox(height: 11),
                      _PlayerStylePicker(
                        selected: playerStyle,
                        onSelected: (style) async {
                          await ref
                              .read(playerVisualStyleProvider.notifier)
                              .select(style);
                          if (!context.mounted) return;
                          showMusicNotice(
                            context,
                            icon: Icons.graphic_eq_rounded,
                            title: '${style.displayName}已应用',
                            message: '打开全屏播放器即可查看新样式',
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      _ThemePreview(
                        preset: selected,
                        effectivePreset: effectiveTheme,
                      ),
                      const SizedBox(height: 21),
                      if (!DistributionChannel.isBeta) ...[
                        const _SettingsHeading(
                          title: '皮肤',
                          description: '选择浅色、深色或跟随系统，角色可在进度条中独立设置。',
                        ),
                        const SizedBox(height: 11),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: DistributionChannel.isBeta
                              ? 1
                              : musicThemeCategories.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 9,
                                mainAxisSpacing: 9,
                                mainAxisExtent: 70,
                              ),
                          itemBuilder: (context, index) {
                            final ip = musicThemeCategories[index];
                            return _IpCategoryCard(
                              ip: ip,
                              active: activeIp == ip,
                              onTap: () {
                                setState(() => _activeIp = ip);
                                if (ip == MusicThemeIp.classic &&
                                    selected.ip != MusicThemeIp.classic) {
                                  ref
                                      .read(musicThemeProvider.notifier)
                                      .select('classic');
                                }
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 13),
                      ],
                      if (staticThemes.isNotEmpty)
                        _PresetGroup(
                          title: '静态皮肤',
                          description: '安静耐看的固定画面',
                          presets: staticThemes,
                          selected: selected,
                          onSelect: (id) =>
                              ref.read(musicThemeProvider.notifier).select(id),
                        ),
                      if (staticThemes.isNotEmpty && motionThemes.isNotEmpty)
                        const SizedBox(height: 22),
                      if (motionThemes.isNotEmpty)
                        _PresetGroup(
                          title: '动态皮肤',
                          description: '角色与场景持续运动',
                          presets: motionThemes,
                          selected: selected,
                          onSelect: (id) =>
                              ref.read(musicThemeProvider.notifier).select(id),
                        ),
                      const SizedBox(height: 25),
                      const _SettingsHeading(
                        title: '自定义皮肤',
                        description: '选择自己的图片或静音循环视频作为音乐空间背景。',
                      ),
                      const SizedBox(height: 11),
                      Wrap(
                        spacing: 9,
                        runSpacing: 9,
                        children: [
                          _SettingsAction(
                            icon: Icons.add_photo_alternate_outlined,
                            label: '选择图片',
                            onTap: () => ref
                                .read(customBackgroundProvider.notifier)
                                .pickImage(),
                          ),
                          _SettingsAction(
                            icon: Icons.video_library_outlined,
                            label: '选择视频',
                            onTap: () => ref
                                .read(customBackgroundProvider.notifier)
                                .pickVideo(),
                          ),
                          if (custom.active)
                            _SettingsAction(
                              icon: Icons.layers_clear_outlined,
                              label: '恢复皮肤',
                              onTap: () => ref
                                  .read(customBackgroundProvider.notifier)
                                  .clear(),
                            ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      const _SettingsHeading(
                        title: '进度条装扮',
                        description: '选角色，搭配同系列轨道；也可以自定义组合。',
                      ),
                      const SizedBox(height: 10),
                      const ProgressOutfitPicker(),
                      const SizedBox(height: 22),
                      if (!DistributionChannel.isBeta)
                        _VisualControls(
                          visual: visual,
                          onStrengthChanged: (value) => ref
                              .read(themeVisualSettingsProvider.notifier)
                              .setBackgroundStrength(value),
                          onDecorationChanged: (value) => ref
                              .read(themeVisualSettingsProvider.notifier)
                              .setIpDecoration(value),
                        ),
                      if (!DistributionChannel.isBeta) ...[
                        const SizedBox(height: 14),
                        _PerformancePicker(
                          selected: performance,
                          onSelected: (value) => ref
                              .read(themePerformanceProvider.notifier)
                              .select(value),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text(
                        '视频背景始终静音播放，并会在应用进入后台时自动暂停。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: MusicTypography.smallCaptionSize,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            top: 16,
            child: _FixedCloseButton(
              onTap: widget.onClose ?? Navigator.of(context).pop,
            ),
          ),
        ],
      ),
    );

    if (widget.embeddedInGlassSheet) {
      return RepaintBoundary(
        key: const ValueKey('theme-gallery-sheet-content'),
        child: content,
      );
    }

    return ClipRRect(
      borderRadius: panelRadius,
      child: BackdropFilter(
        key: const ValueKey('theme-gallery-glass-panel'),
        filter: ImageFilter.blur(
          sigmaX: 22,
          sigmaY: 22,
          tileMode: TileMode.decal,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: panelRadius,
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? .15 : .5),
              width: .8,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  Colors.white.withValues(alpha: dark ? .075 : .28),
                  tokens.glassStrong.withValues(alpha: dark ? .72 : .58),
                ),
                tokens.glass.withValues(alpha: dark ? .68 : .5),
                Color.alphaBlend(
                  accent.withValues(alpha: dark ? .075 : .04),
                  tokens.glassSubtle.withValues(alpha: dark ? .7 : .48),
                ),
              ],
              stops: const [0, .5, 1],
            ),
          ),
          child: content,
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader();

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Padding(
      padding: const EdgeInsets.only(right: 58),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '装扮',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: MusicTypography.titleSize,
              height: 1.1,
              fontWeight: MusicTypography.titleWeight,
              letterSpacing: -.7,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            DistributionChannel.isBeta
                ? '选择启动页、播放器、背景与进度角色，装扮你的音乐空间。'
                : '选择播放器、背景与进度角色，装扮你的音乐空间。',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: MusicTypography.captionSize,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _FixedCloseButton extends StatelessWidget {
  const _FixedCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BetaGlassAction(
      label: '关闭装扮',
      icon: Icons.close_rounded,
      blue: false,
      onPressed: onTap,
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.preset, required this.effectivePreset});

  final MusicThemePreset preset;
  final MusicThemePreset effectivePreset;

  @override
  Widget build(BuildContext context) {
    if (effectivePreset.ip == MusicThemeIp.classic) {
      return _ClassicThemePreview(
        preset: preset,
        effectivePreset: effectivePreset,
      );
    }
    return RepaintBoundary(
      child: Container(
        height: 150,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: effectivePreset.ip == MusicThemeIp.classic
              ? effectivePreset.colors.first
              : null,
          gradient: effectivePreset.ip == MusicThemeIp.classic
              ? null
              : LinearGradient(colors: effectivePreset.colors),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (effectivePreset.backgroundAsset != null)
              Image.asset(
                effectivePreset.mobileBackgroundAsset ??
                    effectivePreset.backgroundAsset!,
                fit: BoxFit.cover,
                alignment: effectivePreset.alignment,
                cacheWidth: 768,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
              ),
            if (effectivePreset.ip != MusicThemeIp.classic)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: .56),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    style: TextStyle(
                      color: preset.ip == MusicThemeIp.classic
                          ? (effectivePreset.dark ? Colors.white : Colors.black)
                          : Colors.white,
                      fontSize: MusicTypography.bodySize,
                      fontWeight: MusicTypography.titleWeight,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preset.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: preset.ip == MusicThemeIp.classic
                          ? (effectivePreset.dark
                                ? Colors.white70
                                : Colors.black54)
                          : Colors.white70,
                      fontSize: MusicTypography.smallCaptionSize,
                    ),
                  ),
                ],
              ),
            ),
            if (preset.followsSystem)
              Positioned(
                right: 13,
                top: 13,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: effectivePreset.dark
                        ? const Color(0x2EFFFFFF)
                        : const Color(0x14000000),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: effectivePreset.dark
                          ? const Color(0x42FFFFFF)
                          : const Color(0x1F000000),
                    ),
                  ),
                  child: Text(
                    effectivePreset.dark ? '当前：深色' : '当前：浅色',
                    style: TextStyle(
                      color: effectivePreset.dark
                          ? Colors.white
                          : Colors.black87,
                      fontSize: MusicTypography.smallCaptionSize,
                      fontWeight: MusicTypography.bodyWeight,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ClassicThemePreview extends StatelessWidget {
  const _ClassicThemePreview({
    required this.preset,
    required this.effectivePreset,
  });

  final MusicThemePreset preset;
  final MusicThemePreset effectivePreset;

  @override
  Widget build(BuildContext context) {
    final dark = effectivePreset.dark;
    final foreground = dark ? Colors.white : const Color(0xFF242329);
    final supporting = foreground.withValues(alpha: .64);
    final modeIcon = preset.followsSystem
        ? Icons.brightness_auto_rounded
        : dark
        ? Icons.dark_mode_rounded
        : Icons.light_mode_rounded;
    final status = preset.followsSystem ? '当前：${dark ? '深色' : '浅色'}' : '已启用';

    return RepaintBoundary(
      key: const ValueKey('classic-theme-preview'),
      child: Container(
        height: 88,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: effectivePreset.colors.first,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: foreground.withValues(alpha: .12)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: foreground.withValues(alpha: .12)),
              ),
              child: Icon(modeIcon, color: foreground, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: MusicTypography.calloutSize,
                      fontWeight: MusicTypography.bodyWeight,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    preset.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: supporting,
                      fontSize: MusicTypography.smallCaptionSize,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: foreground.withValues(alpha: .12)),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: foreground,
                  fontSize: MusicTypography.smallCaptionSize,
                  fontWeight: MusicTypography.bodyWeight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeading extends StatelessWidget {
  const _SettingsHeading({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: MusicTypography.bodySize,
            fontWeight: MusicTypography.titleWeight,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          description,
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: MusicTypography.smallCaptionSize,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _BrandStylePicker extends StatelessWidget {
  const _BrandStylePicker({
    required this.selected,
    required this.applying,
    required this.onSelected,
  });

  final AppBrandStyle selected;
  final AppBrandStyle? applying;
  final ValueChanged<AppBrandStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 164,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ArtworkFrontierPhysics(parent: BouncingScrollPhysics()),
        child: Row(
          children: [
            for (final style in AppBrandStyle.values) ...[
              _BrandStyleCard(
                style: style,
                selected: selected == style,
                applying: applying == style,
                enabled: applying == null,
                onTap: () => onSelected(style),
              ),
              if (style != AppBrandStyle.values.last) const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _BrandStyleCard extends StatelessWidget {
  const _BrandStyleCard({
    required this.style,
    required this.selected,
    required this.applying,
    required this.enabled,
    required this.onTap,
  });

  final AppBrandStyle style;
  final bool selected;
  final bool applying;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 126,
      child: Material(
        color: selected ? accent.withValues(alpha: .12) : tokens.glassSubtle,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: ValueKey('brand-style-${style.id}'),
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? accent : tokens.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: SizedBox(
                    width: 110,
                    height: 104,
                    child: _BrandIconPreview(style: style),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        style.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: MusicTypography.captionSize,
                          fontWeight: MusicTypography.bodyWeight,
                        ),
                      ),
                    ),
                    if (applying)
                      SizedBox.square(
                        dimension: 14,
                        child: MusicActivityIndicator(
                          independent: true,
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    else if (selected)
                      Icon(Icons.check_circle_rounded, size: 16, color: accent),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandIconPreview extends StatelessWidget {
  const _BrandIconPreview({required this.style});

  final AppBrandStyle style;

  @override
  Widget build(BuildContext context) {
    final asset = style.iconAsset;
    if (asset != null) {
      return Image.asset(
        asset,
        key: ValueKey('brand-preview-${style.id}'),
        fit: BoxFit.cover,
        cacheWidth: 320,
        filterQuality: FilterQuality.medium,
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8758D), Color(0xFFD95046)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(19),
        child: Image.asset(
          'assets/branding/mesting-mark-master.png',
          fit: BoxFit.contain,
          cacheWidth: 256,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _PlayerStylePicker extends StatelessWidget {
  const _PlayerStylePicker({required this.selected, required this.onSelected});

  final PlayerVisualStyle selected;
  final ValueChanged<PlayerVisualStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 202,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ArtworkFrontierPhysics(parent: BouncingScrollPhysics()),
        child: Row(
          children: [
            for (final style in PlayerVisualStyle.values) ...[
              _PlayerStyleCard(
                style: style,
                selected: style == selected,
                onTap: () => onSelected(style),
              ),
              if (style != PlayerVisualStyle.values.last)
                const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlayerStyleCard extends StatelessWidget {
  const _PlayerStyleCard({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final PlayerVisualStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = DistributionChannel.isBeta
        ? _galleryActionTint(context)
        : _playerStyleAccent(style);
    return SizedBox(
      width: 134,
      child: Material(
        color: selected ? accent.withValues(alpha: .12) : tokens.glassSubtle,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: ValueKey('player-style-${style.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? accent : tokens.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: _PlayerStylePreview(
                      key: ValueKey('player-preview-${style.id}-$selected'),
                      style: style,
                      active: selected,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        style.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: MusicTypography.captionSize,
                          fontWeight: MusicTypography.bodyWeight,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle_rounded, size: 16, color: accent),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  style.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: MusicTypography.smallCaptionSize,
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

Color _playerStyleAccent(PlayerVisualStyle style) => switch (style) {
  PlayerVisualStyle.cover ||
  PlayerVisualStyle.classic => BetaAppearance.artworkCoral,
  PlayerVisualStyle.aurora => const Color(0xFF6BDCF5),
  PlayerVisualStyle.cassette => const Color(0xFFA78BFA),
  PlayerVisualStyle.lyricStage => const Color(0xFF5EEAD4),
};

class _PlayerStylePreview extends StatelessWidget {
  const _PlayerStylePreview({
    required this.style,
    required this.active,
    super.key,
  });

  final PlayerVisualStyle style;
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (style == PlayerVisualStyle.cover) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            _ClassicPlayerStylePreview.previewCover,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    if (style == PlayerVisualStyle.classic) {
      return _ClassicPlayerStylePreview(active: active);
    }
    return PlayerVisualStagePreview(
      style: style,
      active: active,
      coverAsset: _ClassicPlayerStylePreview.previewCover,
    );
  }
}

class _ClassicPlayerStylePreview extends StatelessWidget {
  const _ClassicPlayerStylePreview({required this.active});

  static const _tonearmAsset = 'assets/images/player/netease-style-tonearm.png';
  static const previewCover =
      'assets/images/theme_playlists/shinchan/cover-01.jpg';
  final bool active;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE1DDDE), Color(0xFFAAA4A6)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shortest = constraints.biggest.shortestSide;
          final recordSize = (shortest * .88).clamp(76.0, 104.0);
          final tonearmWidth = recordSize * .34;
          final tonearmHeight = recordSize * .55;
          return Stack(
            key: const ValueKey('classic-player-turntable-preview'),
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: (constraints.maxWidth - recordSize) / 2,
                bottom: 5,
                width: recordSize,
                height: recordSize,
                child: VinylDisc(
                  key: const ValueKey('classic-player-preview-vinyl'),
                  coverAsset: previewCover,
                  playing: active,
                  rotationDuration: const Duration(milliseconds: 2400),
                  rotationCount: 1,
                  labelSizeFactor: .6,
                ),
              ),
              Positioned(
                left: constraints.maxWidth * .51,
                top: 2,
                width: tonearmWidth,
                height: tonearmHeight,
                child: Transform.rotate(
                  angle: -.05,
                  alignment: const Alignment(-.78, -.86),
                  child: Image.asset(
                    _tonearmAsset,
                    key: const ValueKey('classic-player-preview-tonearm'),
                    fit: BoxFit.contain,
                    cacheWidth: 192,
                    filterQuality: FilterQuality.high,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _IpCategoryCard extends StatelessWidget {
  const _IpCategoryCard({
    required this.ip,
    required this.active,
    required this.onTap,
  });

  final MusicThemeIp ip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final data = switch (ip) {
      MusicThemeIp.classic => ('经典皮肤', 'PURE MUSIC SPACE'),
      MusicThemeIp.shinchan => ('蜡笔小新', 'KASUKABE DAYS'),
      MusicThemeIp.helloKitty => ('Hello Kitty', 'SWEET BOW CLUB'),
      MusicThemeIp.kuromi => ('库洛米', 'MISCHIEF NIGHT'),
      MusicThemeIp.myMelody => ('美乐蒂', 'PROGRESS COMPANION'),
      MusicThemeIp.usagi => ('乌萨奇', 'PROGRESS COMPANION'),
      MusicThemeIp.chiikawa => ('吉伊卡哇', 'PROGRESS COMPANION'),
      MusicThemeIp.hachiware => ('小八', 'PROGRESS COMPANION'),
      MusicThemeIp.puppyWhite => ('小白', 'PROGRESS COMPANION'),
      MusicThemeIp.puppyGray => ('小灰', 'PROGRESS COMPANION'),
      MusicThemeIp.cinnamoroll => ('大耳狗', 'PROGRESS COMPANION'),
      MusicThemeIp.sleepingKirby => ('睡帽卡比', 'PROGRESS COMPANION'),
      MusicThemeIp.nailong => ('雷霆奶龙', 'LAUGHING COMPANION'),
    };
    return Material(
      color: active
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: .82)
          : tokens.glassSubtle,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 70,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? _galleryActionTint(context) : tokens.border,
            ),
          ),
          child: Row(
            children: [
              _IpAvatar(ip: ip),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: MusicTypography.subheadlineSize,
                        fontWeight: MusicTypography.bodyWeight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.$2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: MusicTypography.smallCaptionSize,
                        height: 1.12,
                        fontWeight: MusicTypography.bodyWeight,
                        letterSpacing: .8,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                active
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: active ? _galleryActionTint(context) : tokens.textMuted,
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IpAvatar extends StatelessWidget {
  const _IpAvatar({required this.ip});

  final MusicThemeIp ip;

  @override
  Widget build(BuildContext context) {
    final asset = switch (ip) {
      MusicThemeIp.classic => null,
      MusicThemeIp.shinchan =>
        'assets/images/theme_gallery/shinchan-avatar-v2.png',
      MusicThemeIp.helloKitty =>
        'assets/images/theme_gallery/hello-kitty-progress-head.png',
      MusicThemeIp.kuromi =>
        'assets/images/theme_gallery/kuromi-progress-head.png',
      _ => null,
    };
    final colors = switch (ip) {
      MusicThemeIp.classic => const [Color(0xFFFFFFFF), Color(0xFFDCEEFA)],
      MusicThemeIp.shinchan => const [Color(0xFFFFF9CF), Color(0xFFFFE8D1)],
      MusicThemeIp.helloKitty => const [Color(0xFFFFFAF5), Color(0xFFE4EEFF)],
      MusicThemeIp.kuromi => const [Color(0xFFFBF4FF), Color(0xFFE7D6F0)],
      _ => const [Colors.white, Color(0xFFEAF2FF)],
    };
    return Container(
      width: 38,
      height: 38,
      padding: EdgeInsets.all(ip == MusicThemeIp.kuromi ? 1.5 : 2.5),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: context.musicThemeTokens.border),
      ),
      child: asset == null
          ? const Icon(
              Icons.music_note_rounded,
              color: Color(0xFF356487),
              size: 23,
            )
          : Image.asset(
              asset,
              fit: BoxFit.contain,
              cacheWidth: 128,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
            ),
    );
  }
}

class _PresetGroup extends StatelessWidget {
  const _PresetGroup({
    required this.title,
    required this.description,
    required this.presets,
    required this.selected,
    required this.onSelect,
  });

  final String title;
  final String description;
  final List<MusicThemePreset> presets;
  final MusicThemePreset selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final compactThemeModes =
        presets.length == 3 &&
        presets.every((preset) => preset.ip == MusicThemeIp.classic);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: MusicTypography.subheadlineSize,
                fontWeight: MusicTypography.bodyWeight,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: MusicTypography.smallCaptionSize,
                ),
              ),
            ),
            Text(
              '${presets.length} 套',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: MusicTypography.smallCaptionSize,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (compactThemeModes)
          Row(
            key: const ValueKey('classic-theme-mode-row'),
            children: [
              for (var index = 0; index < presets.length; index++) ...[
                Expanded(
                  child: _ThemeModePresetCard(
                    preset: presets[index],
                    active: presets[index].id == selected.id,
                    onTap: () => onSelect(presets[index].id),
                  ),
                ),
                if (index != presets.length - 1) const SizedBox(width: 8),
              ],
            ],
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: presets.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 9,
              mainAxisSpacing: 9,
              mainAxisExtent: 112,
            ),
            itemBuilder: (context, index) {
              final preset = presets[index];
              return _IllustratedPresetCard(
                preset: preset,
                active: preset.id == selected.id,
                onTap: () => onSelect(preset.id),
              );
            },
          ),
      ],
    );
  }
}

class _ThemeModePresetCard extends StatelessWidget {
  const _ThemeModePresetCard({
    required this.preset,
    required this.active,
    required this.onTap,
  });

  final MusicThemePreset preset;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final mode = preset.followsSystem
        ? ThemeMode.system
        : preset.dark
        ? ThemeMode.dark
        : ThemeMode.light;
    final foreground = mode == ThemeMode.light
        ? const Color(0xFF242329)
        : Colors.white;
    final colors = switch (mode) {
      ThemeMode.light => const [Color(0xFFFFFFFF), Color(0xFFF2EDF0)],
      ThemeMode.dark => const [Color(0xFF25252A), Color(0xFF050506)],
      ThemeMode.system => const [Color(0xFF8C8990), Color(0xFF29282E)],
    };
    final icon = switch (mode) {
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
      ThemeMode.system => Icons.brightness_auto_rounded,
    };
    final shortName = preset.name.replaceFirst('模式', '');
    return Semantics(
      selected: active,
      button: true,
      label: preset.name,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(17),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('theme-mode-${preset.id}'),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 88,
            padding: const EdgeInsets.fromLTRB(10, 9, 8, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: active
                    ? (DistributionChannel.isBeta
                          ? _galleryActionTint(context)
                          : preset.accent)
                    : Colors.white.withValues(
                        alpha: mode == ThemeMode.light ? .74 : .2,
                      ),
                width: active ? 1.8 : .8,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: .17),
                        blurRadius: 15,
                        spreadRadius: -6,
                        offset: const Offset(0, 7),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 31,
                      height: 31,
                      decoration: BoxDecoration(
                        color: foreground.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: foreground.withValues(alpha: .16),
                        ),
                      ),
                      child: Icon(icon, color: foreground, size: 18),
                    ),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: active
                          ? Container(
                              key: const ValueKey('selected'),
                              width: 21,
                              height: 21,
                              decoration: BoxDecoration(
                                color: DistributionChannel.isBeta
                                    ? BetaAppearance.accent(
                                        Theme.of(context).brightness,
                                      )
                                    : preset.accent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: .9),
                                ),
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                            )
                          : const SizedBox.square(
                              key: ValueKey('not-selected'),
                              dimension: 21,
                            ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: MusicTypography.captionSize,
                    fontWeight: MusicTypography.bodyWeight,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  switch (mode) {
                    ThemeMode.light => '明亮',
                    ThemeMode.dark => '夜间',
                    ThemeMode.system => '自动',
                  },
                  style: TextStyle(
                    color: foreground.withValues(alpha: .62),
                    fontSize: MusicTypography.smallCaptionSize,
                    fontWeight: MusicTypography.bodyWeight,
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

class _IllustratedPresetCard extends StatelessWidget {
  const _IllustratedPresetCard({
    required this.preset,
    required this.active,
    required this.onTap,
  });

  final MusicThemePreset preset;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: preset.colors),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (preset.backgroundAsset != null)
                  Image.asset(
                    preset.mobileBackgroundAsset ?? preset.backgroundAsset!,
                    fit: BoxFit.cover,
                    alignment: preset.alignment,
                    cacheWidth: 768,
                    filterQuality: FilterQuality.low,
                    gaplessPlayback: true,
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: .58),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 8,
                  bottom: 8,
                  child: Text(
                    preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: MusicTypography.smallCaptionSize,
                      fontWeight: MusicTypography.bodyWeight,
                    ),
                  ),
                ),
                if (active)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: DistributionChannel.isBeta
                                ? BetaAppearance.accent(
                                    Theme.of(context).brightness,
                                  )
                                : preset.accent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (active)
                  const Positioned(
                    right: 7,
                    top: 7,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.check_rounded, size: 15),
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

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Material(
      color: tokens.glassSubtle,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          constraints: const BoxConstraints(minWidth: 145, minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: _galleryActionTint(context)),
              const SizedBox(width: 9),
              Text(
                label,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: MusicTypography.footnoteSize,
                  fontWeight: MusicTypography.bodyWeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisualControls extends StatelessWidget {
  const _VisualControls({
    required this.visual,
    required this.onStrengthChanged,
    required this.onDecorationChanged,
  });

  final ThemeVisualSettings visual;
  final ValueChanged<double> onStrengthChanged;
  final ValueChanged<bool> onDecorationChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return _SettingSurface(
      child: Column(
        children: [
          if (!DistributionChannel.isBeta) ...[
            Row(
              children: [
                const Expanded(
                  child: _SettingLabel(
                    title: '背景显示强度',
                    description: '内容看不清时可以调低一点',
                  ),
                ),
                Text(
                  '${(visual.backgroundStrength * 100).round()}%',
                  style: const TextStyle(
                    color: Color(0xFF6C80EA),
                    fontSize: MusicTypography.footnoteSize,
                    fontWeight: MusicTypography.bodyWeight,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: BetaAppearance.accent(
                  Theme.of(context).brightness,
                ),
                inactiveTrackColor: tokens.borderStrong,
                trackHeight: 4,
                thumbColor: _galleryActionTint(context),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: visual.backgroundStrength,
                min: .18,
                max: .92,
                onChanged: onStrengthChanged,
              ),
            ),
            Divider(height: 24, color: tokens.border),
          ],
          Row(
            children: [
              const Expanded(
                child: _SettingLabel(
                  title: 'IP 角色装饰',
                  description: '显示当前主题的角色、贴纸与场景元素',
                ),
              ),
              const SizedBox(width: 12),
              _MusicToggle(
                value: visual.showIpDecoration,
                onChanged: onDecorationChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingLabel extends StatelessWidget {
  const _SettingLabel({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: MusicTypography.subheadlineSize,
            fontWeight: MusicTypography.bodyWeight,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          description,
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: MusicTypography.smallCaptionSize,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _MusicToggle extends StatelessWidget {
  const _MusicToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Semantics(
      toggled: value,
      button: true,
      label: 'IP 角色装饰',
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 50,
          height: 28,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? _galleryActionTint(context) : tokens.borderStrong,
            borderRadius: BorderRadius.circular(999),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x332A344E),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: SizedBox.square(dimension: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class _PerformancePicker extends StatelessWidget {
  const _PerformancePicker({required this.selected, required this.onSelected});

  final ThemePerformanceMode selected;
  final ValueChanged<ThemePerformanceMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return _SettingSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SettingLabel(title: '动态效果性能', description: '根据设备性能选择动画完整度'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in ThemePerformanceMode.values)
                    SizedBox(
                      width: width,
                      height: 44,
                      child: Material(
                        color: mode == selected
                            ? const Color(0x1F6C80EA)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(13),
                        child: InkWell(
                          onTap: () => onSelected(mode),
                          borderRadius: BorderRadius.circular(13),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                color: mode == selected
                                    ? const Color(0x9E6C80EA)
                                    : tokens.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  mode == selected
                                      ? Icons.check_circle_rounded
                                      : Icons.circle_outlined,
                                  size: 17,
                                  color: mode == selected
                                      ? BetaAppearance.accent(
                                          Theme.of(context).brightness,
                                        )
                                      : tokens.textMuted,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    switch (mode) {
                                      ThemePerformanceMode.automatic => '自动推荐',
                                      ThemePerformanceMode.full => '完整动效',
                                      ThemePerformanceMode.reduced => '省电静态',
                                    },
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontSize:
                                          MusicTypography.smallCaptionSize,
                                      fontWeight: MusicTypography.bodyWeight,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SettingSurface extends StatelessWidget {
  const _SettingSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.glassSubtle,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.border),
      ),
      child: child,
    );
  }
}
