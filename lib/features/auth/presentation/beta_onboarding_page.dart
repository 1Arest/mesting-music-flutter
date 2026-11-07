import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../themes/theme_controller.dart';
import '../../music_platform/music_platform_providers.dart';
import 'mesting_music_companions.dart';
import 'beta_player_style_previews.dart';
import 'beta_guide_preview.dart';

/// Content is deliberately grounded in the Beta's current capabilities.
/// Demonstrations never write to cloud accounts or start a second player.
const betaGuidePages = <({String title, String body, List<String> tags})>[
  (
    title: '发现你的音乐',
    body:
        '首页提供每日推荐、猜你喜欢、新歌、榜单、新碟、主题与场景音乐，发现页可探索私人 FM 和刷歌推荐。搜索支持歌曲、专辑、歌手、歌单和歌词五类结果。',
    tags: ['首页与发现', '五类搜索', '平台推荐'],
  ),
  (
    title: '播放与歌词',
    body: '轻点底部播放胶囊展开播放器，点击封面查看同步歌词，再点上方封面返回。更多菜单提供歌曲评论、实际可用的音质与播放器风格。',
    tags: ['完整播放器', '同步歌词', '双向切换'],
  ),
  (
    title: '顺手的播放器操作',
    body:
        '从顶部灰条下拉收起播放器。底部可打开歌词、音频输出和待播列表；音频输出面板可调节系统媒体音量，并在同一卡片内选择本机或已连接耳机。新设备先在系统蓝牙设置中完成配对。',
    tags: ['下拉收起', '系统音量', '输出设备'],
  ),
  (
    title: '账号、收藏与签到',
    body:
        '登录酷狗后，可按平台权限使用收藏、个人歌单与评论，并在“我的 → 签到与会员”查看打卡和到期时间。奖励是否新增由平台确认，应用内播放目前不保证计入平台听歌时长。',
    tags: ['酷狗账号', '收藏与歌单', '签到与会员'],
  ),
  (
    title: '让音乐接着播放',
    body:
        '轻点歌曲只播放所选一首，“播放全部”才加入整组。在待播列表按住右侧手柄排序，左滑移除，随机与循环分别设置。手动待播优先，自动推荐有标注；上一首回到真实播放历史。',
    tags: ['拖拽排序', '左滑移除', '手动优先'],
  ),
  (
    title: '调成你的样子',
    body:
        '在“设置 → 装扮”选择浅色、深色或跟随系统，分别设置背景、进度条角色和启动页。启动页保留两张静态图与两段视频；小新进度角色还有七种可独立保存的天气。',
    tags: ['外观模式', '启动页', '进度角色'],
  ),
  (
    title: '五种播放器风格',
    body: '选一个喜欢的舞台，音乐照常继续。这里的选择会保存，也可随时从装扮或播放器更多菜单更换。',
    tags: [],
  ),
  (title: '开始你的音乐之旅', body: '喜欢的音乐与熟悉的操作，都已准备好。以后也能在设置中的“使用指南”重新查看。', tags: []),
];

class BetaOnboardingPage extends ConsumerStatefulWidget {
  const BetaOnboardingPage({
    required this.onFinish,
    this.replay = false,
    super.key,
  });
  final VoidCallback onFinish;

  /// Reopening the guide is dismissible from every page; first-run onboarding
  /// retains its existing skip-to-last flow and completion bookkeeping.
  final bool replay;
  @override
  ConsumerState<BetaOnboardingPage> createState() => BetaOnboardingPageState();
}

class BetaOnboardingPageState extends ConsumerState<BetaOnboardingPage>
    with SingleTickerProviderStateMixin {
  final _pager = PageController();
  int _index = 0;
  int? _skipFrom;
  late final _skip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    value: 1,
  );

  Future<void> _skipToLast() async {
    if (_index == 7 || _skipFrom != null) return;
    final from = _index;
    // Jump the actual pager once; only the outgoing/incoming pages animate.
    // animateToPage(7) would sweep past six unrelated guide illustrations.
    setState(() {
      _skipFrom = from;
      _skip.value = 0;
    });
    _pager.jumpToPage(7);
    try {
      if (MediaQuery.disableAnimationsOf(context)) {
        _skip.value = 1;
      } else {
        await _skip.forward().orCancel;
      }
    } on TickerCanceled {
      return;
    }
    if (mounted) setState(() => _skipFrom = null);
  }

  /// The app-level entry dispatcher owns Android back while this overlay is up.
  void goBack() {
    if (_index > 0) _page(_index - 1);
  }

  @override
  void dispose() {
    _skip.dispose();
    _pager.dispose();
    super.dispose();
  }

  void _page(int index) {
    // PageController rejects a zero-duration scroll activity. Reduced motion
    // uses a real jump, leaving the same page/state and accessible controls.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pager.jumpToPage(index);
      return;
    }
    _pager.animateToPage(
      index,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_index > 0) {
            _page(_index - 1);
          } else {
            widget.onFinish();
          }
        }
      },
      child: Scaffold(
        key: const ValueKey('beta10-onboarding'),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: Theme.of(context).brightness == Brightness.dark
                  ? const [Color(0xFF22181D), Color(0xFF101114)]
                  : const [Color(0xFFFFF0E9), Color(0xFFFFFDFB)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Mesting Music',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFDE5757),
                              ),
                            ),
                          ),
                          BetaGlassButton(
                            height: 42,
                            onPressed: widget.replay
                                ? widget.onFinish
                                : _index == betaGuidePages.length - 1
                                ? null
                                : _skipToLast,
                            child: Text(widget.replay ? '关闭' : '跳过'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _skip,
                        builder: (context, child) {
                          final p = Curves.easeInOutCubic.transform(
                            _skip.value,
                          );
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Opacity(
                                opacity: _skipFrom == null ? 1 : p,
                                child: FractionalTranslation(
                                  translation: Offset(
                                    _skipFrom == null ? 0 : .12 * (1 - p),
                                    0,
                                  ),
                                  child: child,
                                ),
                              ),
                              if (_skipFrom != null)
                                IgnorePointer(
                                  child: Opacity(
                                    opacity: 1 - p,
                                    child: FractionalTranslation(
                                      translation: Offset(-.12 * p, 0),
                                      child: _GuideContent(index: _skipFrom!),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                        child: PageView.builder(
                          controller: _pager,
                          itemCount: betaGuidePages.length,
                          onPageChanged: (value) =>
                              setState(() => _index = value),
                          itemBuilder: (_, index) => TickerMode(
                            enabled: index == _index,
                            child: _GuideContent(index: index),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 8; i++)
                            Semantics(
                              label: '第 ${i + 1} 页，共 8 页',
                              selected: i == _index,
                              child: GestureDetector(
                                onTap: () => _page(i),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 8,
                                  ),
                                  child: AnimatedContainer(
                                    key: ValueKey('guide-progress-$i'),
                                    duration: const Duration(milliseconds: 240),
                                    width: i == _index ? 26 : 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(9),
                                      color: i == _index
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : ink.withValues(alpha: .22),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Row(
                        children: [
                          if (_index > 0) ...[
                            BetaGlassButton(
                              width: 52,
                              height: 52,
                              label: '上一页',
                              onPressed: () => _page(_index - 1),
                              child: const Icon(CupertinoIcons.chevron_back),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: BetaGlassButton(
                              accent: true,
                              key: const ValueKey('guide-next'),
                              onPressed: () => _index == 7
                                  ? widget.onFinish()
                                  : _page(_index + 1),
                              child: Text(_index == 7 ? '开始使用' : '下一步'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideContent extends ConsumerWidget {
  const _GuideContent({required this.index});
  final int index;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = betaGuidePages[index];
    final platform = ref.watch(platformAccountProvider).value;
    final body = index == 3 && platform == null
        ? '游客可浏览公开内容、使用五类搜索并播放开放资源。登录酷狗后使用收藏、个人歌单与评论；签到和会员任务按平台结果展示。手机号验证码和多种扫码方式可在欢迎页选择。'
        : page.body;
    return LayoutBuilder(
      builder: (context, bounds) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 14),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (bounds.maxHeight - 22).clamp(0, double.infinity),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (index == 7)
                const MestingMusicCompanions(height: 225)
              else if (index == 6)
                const SizedBox(
                  width: double.infinity,
                  child: BetaPlayerStylePreviews(),
                )
              else
                GuideAnimatedScene(index: index),
              const SizedBox(height: 26),
              Text(
                index == 3 && platform == null ? '账号与收藏' : page.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 25,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.65,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .8),
                ),
              ),
              const SizedBox(height: 24),
              if (index == 5)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final mode in [
                      ('classic', '浅色'),
                      ('classic-dark', '深色'),
                      ('classic-system', '跟随系统'),
                    ])
                      ChoiceChip(
                        label: Text(
                          mode.$2,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        selected: ref.watch(musicThemeProvider).id == mode.$1,
                        onSelected: (_) => ref
                            .read(musicThemeProvider.notifier)
                            .select(mode.$1),
                      ),
                  ],
                )
              else if (index == 6)
                const SizedBox.shrink()
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final tag in page.tags)
                      Chip(
                        label: Text(
                          tag,
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(fontSize: 12),
                        ),
                        side: BorderSide.none,
                        backgroundColor: const Color(
                          0xFFDE5757,
                        ).withValues(alpha: .12),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compatibility entry for guide previews, isolated from account/audio writes.
class GuideAnimatedScene extends StatelessWidget {
  const GuideAnimatedScene({required this.index, super.key});
  final int index;
  @override
  Widget build(BuildContext context) => BetaGuidePreview(index: index);
}
