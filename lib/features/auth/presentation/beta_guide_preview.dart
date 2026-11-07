import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Small, explicitly interactive operation previews. They describe the current
/// UI without starting playback, calling a platform service or writing accounts.
class BetaGuidePreview extends StatefulWidget {
  const BetaGuidePreview({required this.index, super.key});
  final int index;
  @override
  State<BetaGuidePreview> createState() => _BetaGuidePreviewState();
}

class _BetaGuidePreviewState extends State<BetaGuidePreview> {
  bool _alternate = false;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget row(IconData icon, String title, String subtitle) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 25),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final content = switch (widget.index) {
      0 => [
        row(CupertinoIcons.search, '搜索你想听的', '歌曲 · 专辑 · 歌手 · 歌单 · 歌词'),
        row(
          CupertinoIcons.compass,
          _alternate ? '新歌速递 · 刷歌推荐' : '私人 FM · 每日推荐',
          '从首页和发现页开始探索',
        ),
      ],
      1 => [
        row(
          _alternate
              ? CupertinoIcons.text_alignleft
              : CupertinoIcons.play_rectangle,
          _alternate ? '正在查看歌词' : '小播放条 → 完整播放器',
          _alternate ? '轻点上方封面返回' : '轻点封面切换同步歌词',
        ),
        row(CupertinoIcons.text_bubble, '歌曲评论', '播放器更多菜单中打开评论与回复'),
      ],
      2 => [
        row(
          CupertinoIcons.headphones,
          _alternate ? '选择播放设备' : '音频输出',
          '可切换设备在同一面板中选择',
        ),
        row(CupertinoIcons.speaker_2, '系统媒体音量', '在音频输出卡片中选择本机或已连接耳机'),
      ],
      3 => [
        row(CupertinoIcons.person_crop_circle, '酷狗账号', '手机号验证码 · 微信等扫码方式'),
        row(
          _alternate ? CupertinoIcons.calendar : CupertinoIcons.heart,
          _alternate ? '我的 → 签到与会员' : '收藏与个人歌单',
          _alternate ? '查看平台返回的签到记录与到期时间' : '账号写入在登录后使用',
        ),
      ],
      4 => [
        row(
          CupertinoIcons.line_horizontal_3,
          _alternate ? '下一首先听这首' : '按住右侧手柄拖动',
          '排序只调整待播，不打断当前歌曲',
        ),
        row(CupertinoIcons.trash, '左滑移除待播歌曲', '随机与循环分别设置，自动推荐有标注'),
      ],
      _ => [
        row(CupertinoIcons.paintbrush, '设置 → 装扮', '浅色 · 深色 · 跟随系统'),
        row(
          CupertinoIcons.sparkles,
          _alternate ? '小新七种天气' : '静态启动图与启动视频',
          '启动页、进度角色和播放器分别设置',
        ),
      ],
    };
    return Semantics(
      button: true,
      label: '点按查看${widget.index + 1}页操作示意',
      child: GestureDetector(
        onTap: () => setState(() => _alternate = !_alternate),
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...content,
              const SizedBox(height: 8),
              Text(
                '点按预览操作',
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
