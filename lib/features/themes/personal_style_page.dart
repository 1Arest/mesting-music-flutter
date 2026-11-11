import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/beta_swipe_pages.dart';
import 'personal_style.dart';
import 'personal_decorations.dart';

/// Uses the same retained swipe viewport as Download Manager. Each page owns
/// its scroll position; clicks and horizontal drags share one selected index.
class PersonalStylePage extends ConsumerStatefulWidget {
  const PersonalStylePage({super.key});
  @override
  ConsumerState<PersonalStylePage> createState() => _PersonalStylePageState();
}

class _PersonalStylePageState extends ConsumerState<PersonalStylePage> {
  int _page = 0;
  Future<void> _change(Map<String, Object?> patch) async {
    try {
      final values = patch.length == 1 && patch.containsKey('palette')
          ? personalPaletteBundle(patch['palette']! as String)
          : patch;
      await ref.read(personalStyleProvider.notifier).change(values);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('装扮暂未保存，请重试')));
      }
    }
  }

  Widget _choices(
    String title,
    String key,
    Object? selected,
    List<String> values,
    List<String> labels,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < values.length; i++)
            ChoiceChip(
              key: ValueKey('$key-${values[i]}'),
              label: Text(labels[i]),
              selected: selected == values[i],
              onSelected: (_) => _change({key: values[i]}),
            ),
        ],
      ),
    ],
  );
  Widget _slider(
    String label,
    String key,
    double value,
    double min,
    double max,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: (v) => _change({key: v}),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(personalStyleProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的风格'),
        actions: [
          TextButton(
            onPressed: () async {
              await _change(const PersonalStyle().toJson());
            },
            child: const Text('恢复默认'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _page,
                children: const {0: Text('套装'), 1: Text('歌词'), 2: Text('挂件')},
                onValueChanged: (v) {
                  if (v != null) setState(() => _page = v);
                },
              ),
            ),
            Expanded(
              child: BetaSwipePages(
                index: _page,
                length: 3,
                onChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) => ListView(
                  key: PageStorageKey('personal-style-$index'),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  children: [
                    if (index == 0) ...[
                      _choices(
                        '配色套装',
                        'palette',
                        s.palette,
                        personalPalettes.keys.toList(),
                        personalPalettes.keys.toList(),
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          for (final color in personalPalettes.values)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: CircleAvatar(
                                radius: 10,
                                backgroundColor: color,
                              ),
                            ),
                        ],
                      ),
                      const Text('套装会推荐搭配歌词与挂件，可再逐项调整；进度条搭配独立保留。所有装扮免费，自动保存。'),
                      _choices(
                        '专辑封面相框',
                        'frame',
                        s.frame.name,
                        CoverFrame.values.map((e) => e.name).toList(),
                        const ['默认', '拍立得白边', '邮票边框'],
                      ),
                      SizedBox(
                        height: 130,
                        child: Center(
                          child: SizedBox.square(
                            dimension: 110,
                            child: PersonalCoverFrame(
                              child: ColoredBox(
                                color: s.accent.withValues(alpha: .2),
                                child: const Icon(Icons.music_note, size: 40),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _choices(
                        '歌曲分享卡片',
                        'poster',
                        s.poster.name,
                        PosterTemplate.values.map((e) => e.name).toList(),
                        const ['默认', '演出票根', '杂志封面', '手写便签', '复古磁带标签'],
                      ),
                      _choices(
                        '听歌纪念卡',
                        'keepsake',
                        s.keepsake.name,
                        KeepsakeTemplate.values.map((e) => e.name).toList(),
                        const ['默认', '月度明信片', '年度收藏卡'],
                      ),
                      const Text('在听歌回顾中主动生成，使用所选月份或全年的真实本地记录。'),
                      _choices(
                        '迷你播放器外观',
                        'mini',
                        s.mini.name,
                        MiniPlayerFinish.values.map((e) => e.name).toList(),
                        const ['默认', '磨砂玻璃', '细边金属', '柔和彩色描边'],
                      ),
                      _choices(
                        '听歌氛围（默认关闭）',
                        'atmosphere',
                        s.atmosphere.name,
                        ListeningAtmosphere.values.map((e) => e.name).toList(),
                        const ['关闭', '柔和光晕', '星空氛围', '唱片氛围'],
                      ),
                      if (s.atmosphere != ListeningAtmosphere.off)
                        _slider('氛围强度', 'strength', s.strength, 0, 1),
                      const Text('用于全屏播放器。随播放轻微变化，暂停后静止；这是播放氛围动画，不代表实时节拍分析。'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('发现页音符微光'),
                        subtitle: const Text('招呼语结束后出现一次，约2秒淡出'),
                        value: s.discoveryNotes,
                        onChanged: (v) => _change({'discoveryNotes': v}),
                      ),
                    ],
                    if (index == 1) ...[
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            const Text('城市的灯还亮着'),
                            const SizedBox(height: 12),
                            Text(
                              '今晚，让音乐陪你',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: s.serif ? 'serif' : null,
                                fontSize: s.lyricSize == 0 ? 28 : s.lyricSize,
                                height: s.lineHeight == 0 ? 1.4 : s.lineHeight,
                                fontWeight: s.lyricWeight == 1
                                    ? FontWeight.w400
                                    : FontWeight.w600,
                                color: s.lyricColor == null
                                    ? Theme.of(context).colorScheme.primary
                                    : Color(s.lyricColor!),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text('找回轻松的自己'),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => _change({
                              'lyricSize': 0,
                              'lineHeight': 0,
                              'lyricWeight': 0,
                              'lyricColor': null,
                              'serif': false,
                            }),
                            child: const Text('默认'),
                          ),
                          TextButton(
                            onPressed: () => _change({
                              'lyricSize': 28,
                              'lineHeight': 1.4,
                              'lyricWeight': 2,
                            }),
                            child: const Text('清晰'),
                          ),
                          TextButton(
                            onPressed: () => _change({
                              'lyricSize': 26,
                              'lineHeight': 1.6,
                              'lyricWeight': 1,
                            }),
                            child: const Text('柔和'),
                          ),
                          TextButton(
                            onPressed: () => _change({
                              'lyricSize': 34,
                              'lineHeight': 1.5,
                              'lyricWeight': 2,
                            }),
                            child: const Text('醒目'),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        title: const Text('系统衬线字体'),
                        subtitle: const Text('使用设备提供的字体，不下载字体文件'),
                        value: s.serif,
                        onChanged: (v) => _change({'serif': v}),
                      ),
                      _slider(
                        '字号',
                        'lyricSize',
                        s.lyricSize == 0 ? 28 : s.lyricSize,
                        20,
                        40,
                      ),
                      _slider(
                        '行距',
                        'lineHeight',
                        s.lineHeight == 0 ? 1.4 : s.lineHeight,
                        1.1,
                        2.4,
                      ),
                      const Text('高亮颜色'),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => _change({'lyricColor': null}),
                            child: const Text('默认'),
                          ),
                          for (final color in [
                            Colors.white,
                            ...personalPalettes.values,
                          ])
                            IconButton(
                              tooltip: '歌词颜色',
                              onPressed: () =>
                                  _change({'lyricColor': color.toARGB32()}),
                              icon: Icon(Icons.circle, color: color),
                            ),
                        ],
                      ),
                    ],
                    if (index == 2) ...[
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: PersonalAvatarDecoration(
                            child: CircleAvatar(
                              radius: 46,
                              backgroundColor: s.accent.withValues(alpha: .2),
                              child: const Icon(Icons.person, size: 50),
                            ),
                          ),
                        ),
                      ),
                      _choices(
                        '头像挂件',
                        'accessory',
                        s.accessory.name,
                        AvatarAccessory.values.map((e) => e.name).toList(),
                        const ['无挂件', '音符', '星环', '月牙', '蝴蝶结', '唱片'],
                      ),
                      const SizedBox(height: 16),
                      const Text('装饰仅用于你的个人头像，会员身份标识继续独立展示。'),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
