import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../data/kugou_listening_profile_repository.dart';
import '../domain/kugou_listening_profile.dart';
import '../domain/platform_session.dart';
import '../kugou_listening_profile_providers.dart';
import '../listening_sync/listening_sync_providers.dart';
import 'kugou_medals_page.dart';
import 'platform_avatar.dart';
import '../../themes/music_typography.dart';

typedef KugouOfficialPageOpener = Future<void> Function(Uri uri);

final _gradePage = Uri.parse(
  'https://m.kugou.com/ssr/listen-level/home?ssr_header_param=266431&isHideTitleBar=1&outerFramework=1',
);
final _gradeRules = Uri.parse(
  'https://activity.kugou.com/voo/v-bf6de1d1/index.html',
);
final _rankRules = Uri.parse(
  'https://activity.kugou.com/voo/v-973b9798/index.html',
);
Uri _reportPage(
  KugouListenPeriod period,
  DateTime date,
) => Uri.https('m.kugou.com', '/ssr/listen-report/home', {
  'isHideTitleBar': '1',
  'dimension': '${period.index}',
  'ssr_header_param': '48',
  'ssr_url_param': '266391',
  'date':
      '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}',
});

/// 独立资料订阅边界：官方读取不重建个人页下面的完整音乐库。
class KugouPersonalStatistics extends ConsumerStatefulWidget {
  const KugouPersonalStatistics({
    required this.session,
    this.onOpenOfficial,
    super.key,
  });
  final PlatformSession session;
  final KugouOfficialPageOpener? onOpenOfficial;
  @override
  ConsumerState<KugouPersonalStatistics> createState() =>
      _KugouPersonalStatisticsState();
}

class _KugouPersonalStatisticsState
    extends ConsumerState<KugouPersonalStatistics> {
  KugouListeningProfileReader? _bound;

  @override
  Widget build(BuildContext context) {
    final candidate = ref.watch(kugouListeningProfileReaderProvider);
    final reader = candidate?.belongsTo(widget.session) == true
        ? candidate
        : null;
    if (reader != _bound) {
      _bound = reader;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(reader, _bound)) {
          unawaited(reader?.loadOverview());
        }
      });
    }
    void open(Widget page) =>
        Navigator.of(context).push(betaContentRoute<void>(page));
    Widget contents() {
      final now = ref.read(kugouListeningProfileClockProvider)();
      final total = reader?.statistics(KugouListenPeriod.month, now);
      final age = reader?.grade.value?.musicAge;
      final grade = reader?.grade.value?.level;
      final medal = reader?.medals.value?.total;
      final seconds =
          total?.value?.totalSeconds ?? reader?.grade.value?.seconds;
      final entries =
          <({String id, String value, String label, String hint, Widget page})>[
            (
              id: 'statistics',
              value: seconds == null ? '—' : '${seconds ~/ 3600}小时',
              label: '听歌统计',
              hint: total?.error ?? '查看官方日、周、月、年听歌报告',
              page: KugouListeningStatisticsPage(
                session: widget.session,
                onOpenOfficial: widget.onOpenOfficial,
              ),
            ),
            (
              id: 'age',
              value: age ?? '—',
              label: '乐龄',
              hint: reader?.grade.error ?? '查看酷狗注册乐龄',
              page: KugouMusicAgePage(session: widget.session),
            ),
            (
              id: 'grade',
              value: grade == null ? 'Lv.—' : 'Lv.$grade',
              label: '听歌等级',
              hint: reader?.grade.error ?? '查看官方听歌等级与进度',
              page: KugouListeningGradePage(
                session: widget.session,
                onOpenOfficial: widget.onOpenOfficial,
              ),
            ),
            (
              id: 'medals',
              value: medal == null ? '—' : '$medal枚',
              label: '徽章',
              hint: reader?.medals.error ?? '查看官方勋章收藏馆',
              page: KugouMedalGalleryPage(session: widget.session),
            ),
          ];
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final large = MediaQuery.textScalerOf(context).scale(14) > 21;
            return Wrap(
              children: [
                for (final entry in entries)
                  SizedBox(
                    width: constraints.maxWidth / (large ? 2 : 4),
                    child: Tooltip(
                      message: entry.hint,
                      child: CupertinoButton(
                        key: ValueKey('kugou-personal-${entry.id}'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 12,
                        ),
                        onPressed: () => open(entry.page),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              entry.value,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: MusicTypography.bodySize,
                                fontWeight: MusicTypography.titleWeight,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entry.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: MusicTypography.captionSize,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    return reader == null
        ? contents()
        : ListenableBuilder(listenable: reader, builder: (_, _) => contents());
  }
}

/// 三个详情页公用同一个账号周期的Reader。旧账号页面只显示已切换提示。
abstract class _KugouProfileState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> {
  KugouListeningProfileReader? _bound;
  PlatformSession get session;
  void load(KugouListeningProfileReader reader);
  KugouListeningProfileReader? bind() {
    final candidate = ref.watch(kugouListeningProfileReaderProvider);
    final reader = candidate?.belongsTo(session) == true ? candidate : null;
    if (!identical(reader, _bound)) {
      _bound = reader;
      if (reader != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && identical(reader, _bound)) {
            load(reader);
          }
        });
      }
    }
    return reader;
  }
}

class KugouListeningStatisticsPage extends ConsumerStatefulWidget {
  const KugouListeningStatisticsPage({
    required this.session,
    this.onOpenOfficial,
    this.initialPeriod = KugouListenPeriod.week,
    this.initialDate,
    super.key,
  });
  final PlatformSession session;
  final KugouOfficialPageOpener? onOpenOfficial;
  final KugouListenPeriod initialPeriod;
  final DateTime? initialDate;
  @override
  ConsumerState<KugouListeningStatisticsPage> createState() =>
      _KugouListeningStatisticsPageState();
}

class _KugouListeningStatisticsPageState
    extends _KugouProfileState<KugouListeningStatisticsPage> {
  KugouListenPeriod _period = KugouListenPeriod.week;
  late DateTime _date;
  @override
  PlatformSession get session => widget.session;
  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
    _date = _period.start(widget.initialDate ?? _latest);
  }

  @override
  void load(KugouListeningProfileReader reader) =>
      unawaited(reader.loadStatistics(_period, _date));
  DateTime get _latest => _period == KugouListenPeriod.year
      ? DateTime(
          math.min(
            KugouListeningProfileRepository.lastAnnualYear,
            ref.read(kugouListeningProfileClockProvider)().year - 1,
          ),
        )
      : _period.start(ref.read(kugouListeningProfileClockProvider)());
  void _select(KugouListenPeriod period) {
    setState(() {
      _period = period;
      _date = period == KugouListenPeriod.year
          ? _latest
          : period.start(ref.read(kugouListeningProfileClockProvider)());
    });
    final reader = _bound;
    if (reader != null) {
      load(reader);
    }
  }

  void _shift(int direction) {
    setState(() => _date = _period.shift(_date, direction));
    final reader = _bound;
    if (reader != null) {
      load(reader);
    }
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(KugouListeningProfileRepository.firstAnnualYear),
      lastDate: _latest,
    );
    if (!mounted || date == null) {
      return;
    }
    setState(() => _date = _period.start(date));
    final reader = _bound;
    if (reader != null) {
      load(reader);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reader = bind();
    Widget contents() {
      final state = reader?.statistics(_period, _date);
      final stats = state?.value;
      final rows = stats?.rows('rank_song') ?? const <Map<String, dynamic>>[];
      return _KugouProfileFrame(
        title: '听歌统计',
        session: session,
        showIdentity: reader != null,
        loading: state?.loading == true,
        onRefresh: reader == null
            ? null
            : () => reader.loadStatistics(_period, _date, force: true),
        children: reader == null
            ? const [_AccountChanged()]
            : [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final period in KugouListenPeriod.values)
                      ChoiceChip(
                        label: Text(period.label),
                        selected: _period == period,
                        onSelected: (_) => _select(period),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '上一${_period.label}',
                        onPressed:
                            _period == KugouListenPeriod.year &&
                                _date.year <=
                                    KugouListeningProfileRepository
                                        .firstAnnualYear
                            ? null
                            : () => _shift(-1),
                        icon: const Icon(CupertinoIcons.chevron_left),
                      ),
                      Expanded(
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: _chooseDate,
                          child: Text(
                            _periodDate(_period, _date),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: MusicTypography.headingSize,
                              fontWeight: MusicTypography.titleWeight,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '下一${_period.label}',
                        onPressed: _date.isBefore(_latest)
                            ? () => _shift(1)
                            : null,
                        icon: const Icon(CupertinoIcons.chevron_right),
                      ),
                    ],
                  ),
                ),
                if (_period == KugouListenPeriod.year)
                  _Note('年度报告按酷狗已发布年份读取。最新可读取年份为${_latest.year}年。'),
                _ReadFeedback(
                  state: state,
                  onRetry: () =>
                      reader.loadStatistics(_period, _date, force: true),
                ),
                if (stats != null) ...[
                  _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _eyebrow(
                          context,
                          '${_period == KugouListenPeriod.year ? '年度' : '本${_period.label}'}收听',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          stats.seconds == null
                              ? '官方暂未返回时长'
                              : kugouDuration(stats.seconds),
                          style: const TextStyle(
                            fontSize: MusicTypography.largeTitleSize,
                            fontWeight: MusicTypography.titleWeight,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 24,
                          runSpacing: 8,
                          children: [
                            if (stats.days != null)
                              Text(
                                '${stats.days}天 · ${stats.annual ? '年度活跃' : '听歌天数'}',
                              ),
                            if (stats.songCount != null)
                              Text(
                                '${stats.songCount}首 · ${stats.annual ? '年度歌曲' : '收听歌曲'}',
                              ),
                            if (stats.totalSeconds != null)
                              Text('累计听歌 ${kugouDuration(stats.totalSeconds)}'),
                          ],
                        ),
                        if (stats.seconds == 0)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text('这段时间官方暂未记录有效收听。'),
                          ),
                        const SizedBox(height: 16),
                        _ReadTime(stats.readAt),
                      ],
                    ),
                  ),
                  if (stats.series.isNotEmpty)
                    _StatisticsChart(statistics: stats),
                  if (rows.isNotEmpty) ...[
                    _SectionTitle('歌曲收听榜'),
                    _Panel(
                      child: Column(
                        children: [
                          for (var index = 0; index < rows.length; index++)
                            _RankSong(row: rows[index], rank: index + 1),
                        ],
                      ),
                    ),
                  ],
                  if (stats.rows('rank_singer').isNotEmpty) ...[
                    _SectionTitle('歌手收听榜'),
                    _Panel(
                      child: Column(
                        children: [
                          for (final row in stats.rows('rank_singer'))
                            _RankSinger(row: row),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 18),
                _OfficialButton(
                  label: '查看完整官方报告与排行榜',
                  uri: _reportPage(_period, _date),
                  opener: widget.onOpenOfficial,
                ),
                _OfficialDailyReadback(session: session),
              ],
      );
    }

    return reader == null
        ? contents()
        : ListenableBuilder(listenable: reader, builder: (_, _) => contents());
  }
}

class KugouListeningGradePage extends ConsumerStatefulWidget {
  const KugouListeningGradePage({
    required this.session,
    this.onOpenOfficial,
    this.initialRank = KugouGradeRank.global,
    super.key,
  });
  final PlatformSession session;
  final KugouOfficialPageOpener? onOpenOfficial;
  final KugouGradeRank initialRank;
  @override
  ConsumerState<KugouListeningGradePage> createState() =>
      _KugouListeningGradePageState();
}

class _KugouListeningGradePageState
    extends _KugouProfileState<KugouListeningGradePage> {
  @override
  PlatformSession get session => widget.session;
  @override
  void load(KugouListeningProfileReader reader) =>
      unawaited(reader.loadGrade());
  @override
  Widget build(BuildContext context) {
    final reader = bind();
    Widget contents() {
      final grade = reader?.grade.value;
      return _KugouProfileFrame(
        title: '听歌等级',
        session: session,
        showIdentity: reader != null,
        loading: reader?.grade.loading == true,
        onRefresh: reader == null
            ? null
            : () async {
                await Future.wait([reader.loadGrade(force: true)]);
              },
        tailSlivers: reader == null
            ? const []
            : [
                _KugouGradeRanks(
                  key: ObjectKey(reader),
                  reader: reader,
                  initialKind: widget.initialRank,
                  onOpenOfficial: widget.onOpenOfficial,
                ),
              ],
        children: reader == null
            ? const [_AccountChanged()]
            : [
                _ReadFeedback(
                  state: reader.grade,
                  onRetry: () => reader.loadGrade(force: true),
                ),
                if (grade != null)
                  _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _eyebrow(context, '酷狗听歌等级'),
                        const SizedBox(height: 12),
                        Text(
                          grade.level == null ? '等级暂未返回' : 'Lv.${grade.level}',
                          style: const TextStyle(
                            fontSize: 54,
                            fontWeight: MusicTypography.titleWeight,
                          ),
                        ),
                        if (grade.points != null &&
                            grade.nextPoints != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            '${grade.points} / ${grade.nextPoints} 听歌值',
                            style: const TextStyle(
                              fontSize: MusicTypography.bodySize,
                            ),
                          ),
                        ],
                        if (grade.progress != null) ...[
                          const SizedBox(height: 16),
                          Semantics(
                            label: '升级进度 ${(grade.progress! * 100).round()}%',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: grade.progress,
                                minHeight: 8,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (grade.nextLevel != null)
                          Text('下一等级 Lv.${grade.nextLevel}'),
                        if (grade.points != null &&
                            grade.nextPoints != null &&
                            grade.nextPoints! > grade.points!)
                          Text('还需 ${grade.nextPoints! - grade.points!} 听歌值'),
                        if (grade.speed != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('当前官方加速 ${grade.speed}倍'),
                          ),
                        if (grade.seconds != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text('累计听歌 ${kugouDuration(grade.seconds)}'),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '乐龄 ${reader.grade.value?.musicAge ?? '官方暂未返回'}',
                          ),
                        ),
                        const SizedBox(height: 16),
                        _ReadTime(grade.readAt),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                _OfficialButton(
                  label: '等级规则',
                  uri: _gradeRules,
                  opener: widget.onOpenOfficial,
                ),
                const SizedBox(height: 12),
                _OfficialButton(
                  label: '打开官方等级详情',
                  uri: _gradePage,
                  opener: widget.onOpenOfficial,
                ),
              ],
      );
    }

    return reader == null
        ? contents()
        : ListenableBuilder(listenable: reader, builder: (_, _) => contents());
  }
}

class _GradeRankCache {
  final rows = <Map<String, dynamic>>[];
  KugouGradeRanking? snapshot;
  bool loading = false;
  String? error;
  // 无法确认的写入先锁住；成功重读后才开放下一次操作。
  final uncertainLikes = <String>{};
}

/// 榜单单独持有分页与操作状态，切换榜单不清空已读内容或混入好友收听榜。
class _KugouGradeRanks extends StatefulWidget {
  const _KugouGradeRanks({
    required this.reader,
    this.onOpenOfficial,
    this.initialKind = KugouGradeRank.global,
    super.key,
  });
  final KugouListeningProfileReader reader;
  final KugouOfficialPageOpener? onOpenOfficial;
  final KugouGradeRank initialKind;
  @override
  State<_KugouGradeRanks> createState() => _KugouGradeRanksState();
}

class _KugouGradeRanksState extends State<_KugouGradeRanks> {
  KugouGradeRank _kind = KugouGradeRank.global;
  final _cache = {
    for (final kind in KugouGradeRank.values) kind: _GradeRankCache(),
  };
  final _writing = <String>{};
  bool _cityBusy = false, _cityUncertain = false, _cityChoosing = false;
  KugouRankingCities? _cities;
  String? _message;
  KugouListeningProfileReader get reader => widget.reader;
  bool get _current => mounted && reader.belongsTo(reader.owner);
  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    unawaited(_load(_kind));
  }

  Future<void> _load(KugouGradeRank kind, {bool next = false}) async {
    final state = _cache[kind]!;
    if (!_current || state.loading) {
      return;
    }
    final page = next ? (state.snapshot?.page ?? 0) + 1 : 1;
    setState(() {
      state.loading = true;
      state.error = null;
    });
    try {
      final data = await reader.repository.ranking(
        reader.owner,
        kind,
        page: page,
      );
      if (!_current) {
        return;
      }
      setState(() {
        if (!next) {
          state.rows.clear();
        }
        // 服务分页重复项只保留一份；不推造总数或下一页游标。
        final ids = state.rows.map((row) => '${row['userid']}').toSet();
        state.rows.addAll(
          data.items.where((row) => ids.add('${row['userid']}')),
        );
        state.snapshot = data;
        if (!next) {
          state.uncertainLikes.clear();
          _cityUncertain = false;
        }
      });
    } catch (_) {
      if (_current) {
        setState(() => state.error = '榜单资料读取失败，请重试；已取得的内容保留。');
      }
    } finally {
      if (_current) {
        setState(() => state.loading = false);
      }
    }
  }

  Future<void> _like(KugouGradeRank kind, Map<String, dynamic> row) async {
    final id = '${row['userid'] ?? ''}', key = '${kind.code}:${row['userid']}';
    final state = _cache[kind]!;
    if (!_current ||
        _writing.contains(key) ||
        state.uncertainLikes.contains(id)) {
      return;
    }
    final liked =
        row['is_liked_today'] == true || '${row['is_liked_today']}' == '1';
    setState(() {
      _writing.add(key);
      _message = null;
    });
    try {
      await reader.repository.setRankLiked(
        reader.owner,
        kind,
        id,
        liked: !liked,
      );
      if (!_current) {
        return;
      }
      // 接受回执后更新可见状态；稍后的重读仍以服务为准。
      setState(() {
        row['is_liked_today'] = !liked;
        final count = kugouNonnegative(row['like_num']);
        if (count != null) {
          row['like_num'] = math.max(0, count + (liked ? -1 : 1));
        }
        if ('${state.snapshot?.self['userid']}' == id) {
          state.snapshot?.raw['self_info'] = row;
        }
      });
    } catch (_) {
      if (_current) {
        setState(() {
          state.uncertainLikes.add(id);
          _message = '点赞状态尚未确认，请先刷新榜单核对后再操作。';
        });
      }
    } finally {
      if (_current) {
        setState(() => _writing.remove(key));
      }
    }
  }

  Future<void> _chooseCity() async {
    if (!_current || _cityBusy || _cityChoosing || _cityUncertain) {
      return;
    }
    setState(() {
      _cityBusy = true;
      _message = null;
    });
    try {
      _cities ??= await reader.repository.rankingCities(reader.owner);
      if (!mounted || !_current) {
        return;
      }
      if (_cities!.provinces.isEmpty) {
        setState(() => _message = '酷狗暂未返回可选地区，请稍后重试。');
        return;
      }
      final area = _cache[_kind]!.snapshot?.area ?? const <String, dynamic>{};
      final updateAt = kugouNonnegative(area['next_updatetime']);
      final nowSeconds =
          reader.repository.clock().millisecondsSinceEpoch ~/ 1000;
      if (updateAt != null && updateAt > nowSeconds) {
        final date = DateTime.fromMillisecondsSinceEpoch(updateAt * 1000);
        setState(
          () => _message =
              '当前地区暂不能修改，官方下次可修改日期为${date.year}年${date.month}月${date.day}日。',
        );
        return;
      }
      setState(() {
        _cityBusy = false;
        _cityChoosing = true;
      });
      final choice = await Navigator.of(context).push<Map<String, dynamic>>(
        betaContentRoute(_RankingCityPicker(catalog: _cities!)),
      );
      if (!mounted || !_current || choice == null) {
        return;
      }
      final label = '${choice['full_name'] ?? choice['name'] ?? ''}';
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (dialog) => CupertinoAlertDialog(
          title: const Text('确认榜单地区', style: MusicTypography.titleEmphasis),
          content: Text('设为$label？酷狗规定90天内只可修改一次地区。'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('返回修改', style: MusicTypography.regularText),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('确认提交', style: MusicTypography.regularText),
            ),
          ],
        ),
      );
      if (!_current || confirmed != true) {
        return;
      }
      setState(() => _cityBusy = true);
      try {
        await reader.repository.setRankingCity(
          reader.owner,
          '${choice['area_code'] ?? ''}',
        );
        if (!_current) {
          return;
        }
        setState(() {
          _message = '榜单地区已提交，正在读取官方结果。';
          _cityUncertain = true;
        });
      } catch (_) {
        if (!_current) {
          return;
        }
        setState(() {
          _message = '地区提交结果尚未确认，请先刷新榜单核对，暂不重复提交。';
          _cityUncertain = true;
        });
      }
      await _load(_kind);
    } catch (_) {
      if (_current) {
        setState(() => _message = '可选地区读取失败，请重试。');
      }
    } finally {
      if (_current) {
        setState(() {
          _cityBusy = false;
          _cityChoosing = false;
        });
      }
    }
  }

  Widget _row(
    Map<String, dynamic> row, {
    required bool mine,
    required int fallback,
  }) {
    final id = '${row['userid'] ?? ''}', key = '${_kind.code}:${row['userid']}';
    final rank = kugouNonnegative(row['rank']);
    final points = kugouNonnegative(row['p_current_point']);
    final distance = kugouNonnegative(row['rank_distance']);
    final likes = kugouNonnegative(row['like_num']);
    final liked =
        row['is_liked_today'] == true || '${row['is_liked_today']}' == '1';
    final blocked = _cache[_kind]!.uncertainLikes.contains(id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  rank != null && rank > 0
                      ? '$rank'
                      : mine
                      ? '—'
                      : '$fallback',
                  style: const TextStyle(
                    fontWeight: MusicTypography.titleWeight,
                  ),
                ),
              ),
              PlatformAvatar(
                url: PlatformSession.picture(row['avatar']),
                size: 42,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['nickname'] ?? '酷狗用户'}${mine ? ' · 我' : ''}',
                      style: const TextStyle(
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                    Text(
                      points == null ? '听歌值暂未返回' : '听歌值 $points',
                      style: const TextStyle(
                        fontSize: MusicTypography.footnoteSize,
                      ),
                    ),
                    if (mine && (rank == null || rank == 0))
                      Text(
                        distance == null ? '未上榜' : '还差$distance上榜',
                        style: const TextStyle(
                          fontSize: MusicTypography.captionSize,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: ValueKey('kugou-level-like-${_kind.code}-$id'),
              onPressed:
                  _writing.contains(key) || blocked || int.tryParse(id) == null
                  ? null
                  : () => _like(_kind, row),
              icon: _writing.contains(key)
                  ? const BetaActivityIndicator(radius: 8)
                  : Icon(
                      liked
                          ? CupertinoIcons.hand_thumbsup_fill
                          : CupertinoIcons.hand_thumbsup,
                      size: 19,
                    ),
              label: Text(blocked ? '先刷新核对' : '${likes ?? '—'}'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _cache[_kind]!, snapshot = _cache[_kind]!.snapshot;
    final area = snapshot?.area ?? const <String, dynamic>{};
    final label =
        _kind == KugouGradeRank.province && area['province_name'] != null
        ? '${area['province_name']}月榜'
        : _kind == KugouGradeRank.city && area['city_name'] != null
        ? '${area['city_name']}周榜'
        : _kind.label;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('听歌等级排行榜'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kind in KugouGradeRank.values)
                    ChoiceChip(
                      key: ValueKey('kugou-grade-rank-${kind.code}'),
                      label: Text(kind.label),
                      selected: _kind == kind,
                      onSelected: (_) {
                        setState(() => _kind = kind);
                        if (_cache[kind]!.snapshot == null) {
                          unawaited(_load(kind));
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _cityBusy || _cityChoosing || _cityUncertain
                        ? null
                        : _chooseCity,
                    icon: _cityBusy
                        ? const BetaActivityIndicator(radius: 8)
                        : const Icon(CupertinoIcons.location, size: 18),
                    label: const Text('榜单地区'),
                  ),
                  TextButton(
                    onPressed: state.loading ? null : () => _load(_kind),
                    child: const Text('刷新榜单'),
                  ),
                  TextButton(
                    onPressed: () => _openOfficial(
                      context,
                      widget.onOpenOfficial,
                      _rankRules,
                    ),
                    child: const Text('榜单规则'),
                  ),
                ],
              ),
              if (_message != null) _Note(_message!),
              if (state.error != null) _Note(state.error!),
              if (snapshot != null) ...[
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: MusicTypography.headingSize,
                    fontWeight: MusicTypography.titleWeight,
                  ),
                ),
                if (snapshot.periodEndTime != null)
                  _Note(_settlementDate(snapshot.periodEndTime!)),
                if (snapshot.self.isNotEmpty)
                  _Panel(child: _row(snapshot.self, mine: true, fallback: 0)),
                if (state.rows.isEmpty)
                  _Note(
                    _kind != KugouGradeRank.global && area['city_name'] == null
                        ? '请先设置榜单地区'
                        : '官方暂未返回排名',
                  ),
              ],
            ],
          ),
        ),
        // 真正的Sliver按可见区域构建；连续续页不会把全部榜单塞进一个Column。
        SliverList.builder(
          itemCount: state.rows.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _Panel(
              child: _row(state.rows[index], mine: false, fallback: index + 1),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            children: [
              if (snapshot != null)
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: _ReadTime(snapshot.readAt),
                ),
              if (state.loading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: BetaActivityIndicator()),
                ),
              if (!state.loading &&
                  snapshot?.hasMore(state.rows.length) == true)
                TextButton(
                  onPressed: () => _load(_kind, next: true),
                  child: const Text('加载更多排名'),
                ),
              if (!state.loading && snapshot == null)
                TextButton(
                  onPressed: () => _load(_kind),
                  child: const Text('读取榜单'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _settlementDate(int seconds) {
    final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return '${time.year}年${time.month}月${time.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}结榜';
  }
}

class _RankingCityPicker extends StatefulWidget {
  const _RankingCityPicker({required this.catalog});
  final KugouRankingCities catalog;
  @override
  State<_RankingCityPicker> createState() => _RankingCityPickerState();
}

class _RankingCityPickerState extends State<_RankingCityPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final rows = <({Map<String, dynamic> city, String province})>[];
    for (final province in widget.catalog.provinces) {
      for (final city in KugouRankingCities.cities(province)) {
        final text =
            '${province['name'] ?? ''} ${city['name'] ?? ''} ${city['full_name'] ?? ''}';
        if (text.contains(_query.trim())) {
          rows.add((city: city, province: '${province['name'] ?? ''}'));
        }
      }
    }
    return BetaMusicChromeCover(
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const BetaGlassBackButton(),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '选择榜单地区',
                        style: TextStyle(
                          fontSize: MusicTypography.sectionTitleSize,
                          fontWeight: MusicTypography.titleWeight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: CupertinoSearchTextField(
                  placeholder: '搜索省份或城市',
                  onChanged: (text) => setState(() => _query = text),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text('90天内只可修改一次地区，选择后会再次确认。'),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      title: Text('${row.city['name'] ?? ''}'),
                      subtitle: Text(row.province),
                      onTap: () => Navigator.pop(context, row.city),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 只展示独立官方前后快照，不将增长归因给某一段上报或Mesting播放。
class _OfficialDailyReadback extends ConsumerWidget {
  const _OfficialDailyReadback({required this.session});
  final PlatformSession session;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(kugouOfficialDailySyncStatusProvider).value;
    if (value == null || value.ownerId != session.ownerId) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '官方今日收听核对',
              style: TextStyle(
                fontSize: MusicTypography.bodySize,
                fontWeight: MusicTypography.titleWeight,
              ),
            ),
            const SizedBox(height: 10),
            Text('官方今日时长 ${kugouDuration(value.seconds)}'),
            if (value.readFailed) const _Note('本次官方读取失败，保留上次官方结果。'),
            if (value.observedIncreaseSeconds != null)
              Text('两次官方读取间增加 ${kugouDuration(value.observedIncreaseSeconds)}'),
            if (value.correctedDownward) const _Note('官方时长已作向下调整，当前展示最新官方值。'),
            if (value.readAt != null) _ReadTime(value.readAt!),
            const _Note('此处为官方服务的独立读取结果，其他客户端收听也可能影响增长。'),
            TextButton(
              onPressed: () =>
                  ref.read(platformListeningSyncProvider).verifyPending(),
              child: const Text('重新读取官方结果'),
            ),
          ],
        ),
      ),
    );
  }
}

class KugouMusicAgePage extends ConsumerStatefulWidget {
  const KugouMusicAgePage({required this.session, super.key});
  final PlatformSession session;
  @override
  ConsumerState<KugouMusicAgePage> createState() => _KugouMusicAgePageState();
}

class _KugouMusicAgePageState extends _KugouProfileState<KugouMusicAgePage> {
  @override
  PlatformSession get session => widget.session;
  @override
  void load(KugouListeningProfileReader reader) =>
      unawaited(reader.loadGrade());
  @override
  Widget build(BuildContext context) {
    final reader = bind();
    Widget contents() => _KugouProfileFrame(
      title: '乐龄',
      session: session,
      showIdentity: reader != null,
      loading: reader?.grade.loading == true,
      onRefresh: reader == null ? null : () => reader.loadGrade(force: true),
      children: reader == null
          ? const [_AccountChanged()]
          : [
              _ReadFeedback(
                state: reader.grade,
                onRetry: () => reader.loadGrade(force: true),
              ),
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _eyebrow(context, '在酷狗相伴'),
                    const SizedBox(height: 12),
                    Text(
                      reader.grade.value?.musicAge ?? '官方暂未返回乐龄资料',
                      style: const TextStyle(
                        fontSize: MusicTypography.largeTitleSize,
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('乐龄按酷狗账号注册时间与官方服务器时间，依官方等级页的30天/月、360天/年规则计算。'),
                    if (reader.grade.value != null) ...[
                      const SizedBox(height: 16),
                      _ReadTime(reader.grade.value!.readAt),
                    ],
                  ],
                ),
              ),
            ],
    );
    return reader == null
        ? contents()
        : ListenableBuilder(listenable: reader, builder: (_, _) => contents());
  }
}

class _KugouProfileFrame extends StatelessWidget {
  const _KugouProfileFrame({
    required this.title,
    required this.session,
    required this.children,
    required this.loading,
    this.showIdentity = true,
    this.tailSlivers = const [],
    this.onRefresh,
  });
  final String title;
  final PlatformSession session;
  final List<Widget> children;
  final bool loading, showIdentity;
  final List<Widget> tailSlivers;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) => BetaMusicChromeCover(
    child: Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Row(
                children: [
                  const BetaGlassBackButton(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize:
                            MediaQuery.textScalerOf(context).scale(14) > 21
                            ? MusicTypography.headingSize
                            : MusicTypography.titleSize,
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  BetaGlassButton(
                    width: 48,
                    height: 48,
                    label: '刷新',
                    loading: loading,
                    onPressed: onRefresh == null
                        ? null
                        : () => unawaited(onRefresh!()),
                    child: const Icon(CupertinoIcons.refresh, size: 21),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  if (onRefresh != null)
                    CupertinoSliverRefreshControl(onRefresh: onRefresh),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 32),
                    sliver: SliverList.list(
                      children: [
                        if (showIdentity)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 22),
                            child: Row(
                              children: [
                                PlatformAvatar(
                                  url: session.avatarUrl,
                                  size: 48,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    session.nickname.isEmpty
                                        ? '酷狗用户'
                                        : session.nickname,
                                    style: const TextStyle(
                                      fontSize: MusicTypography.headingSize,
                                      fontWeight: MusicTypography.titleWeight,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ...children,
                      ],
                    ),
                  ),
                  if (tailSlivers.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
                      sliver: SliverMainAxisGroup(slivers: tailSlivers),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .35),
      ),
    ),
    child: child,
  );
}

Widget _eyebrow(BuildContext context, String label) => Text(
  label,
  style: TextStyle(
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    fontSize: MusicTypography.subheadlineSize,
  ),
);

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 25, bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: MusicTypography.sectionTitleSize,
        fontWeight: MusicTypography.titleWeight,
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        height: 1.5,
      ),
    ),
  );
}

class _ReadTime extends StatelessWidget {
  const _ReadTime(this.time);
  final DateTime time;
  @override
  Widget build(BuildContext context) => Text(
    '官方资料 · ${time.month}月${time.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}读取',
    style: TextStyle(
      fontSize: MusicTypography.captionSize,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _AccountChanged extends StatelessWidget {
  const _AccountChanged();
  @override
  Widget build(BuildContext context) => const _Note('当前酷狗账号已变化，请返回个人页后重新打开。');
}

class _ReadFeedback extends StatelessWidget {
  const _ReadFeedback({required this.state, required this.onRetry});
  final KugouProfileRead<Object?>? state;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) {
    if (state?.loading == true && state?.value == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: BetaActivityIndicator()),
      );
    }
    if (state?.error == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${state!.error}${state!.value != null ? '，已保留上次官方结果。' : ''}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 10),
            onPressed: state!.loading ? null : () => unawaited(onRetry()),
            child: const Text('重试这项资料'),
          ),
        ],
      ),
    );
  }
}

class _OfficialButton extends StatelessWidget {
  const _OfficialButton({
    required this.label,
    required this.uri,
    required this.opener,
  });
  final String label;
  final Uri uri;
  final KugouOfficialPageOpener? opener;
  @override
  Widget build(BuildContext context) => BetaGlassButton(
    height: math.max(52, MediaQuery.textScalerOf(context).scale(15) * 2.4),
    label: label,
    onPressed: () => _openOfficial(context, opener, uri),
    child: Text(label, textAlign: TextAlign.center),
  );
}

Future<void> _openOfficial(
  BuildContext context,
  KugouOfficialPageOpener? opener,
  Uri uri,
) async {
  try {
    if (opener == null) {
      throw StateError('Official page unavailable');
    }
    await opener(uri);
    return;
  } catch (_) {
    if (!context.mounted) {
      return;
    }
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: const Text('官方页面未能打开', style: MusicTypography.titleEmphasis),
        content: const Text('请检查网络并重试；如提示授权失效，请重新验证酷狗登录。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('知道了', style: MusicTypography.regularText),
          ),
        ],
      ),
    );
  }
}

class _RankSong extends StatelessWidget {
  const _RankSong({required this.row, required this.rank});
  final Map<String, dynamic> row;
  final int rank;
  @override
  Widget build(BuildContext context) {
    final song = kugouObject(row['song_info']);
    final cover = PlatformSession.picture(song['cover']);
    final count = kugouNonnegative(row['count']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 25,
            child: Text(
              '$rank',
              style: const TextStyle(fontWeight: MusicTypography.titleWeight),
            ),
          ),
          if (cover.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: ArtworkImage(uri: cover, width: 44, height: 44),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${song['name'] ?? '歌曲名称暂未返回'}',
                  style: const TextStyle(
                    fontWeight: MusicTypography.titleWeight,
                  ),
                ),
                if ('${song['singer_name'] ?? ''}'.isNotEmpty)
                  Text(
                    '${song['singer_name']}',
                    style: TextStyle(
                      fontSize: MusicTypography.footnoteSize,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (count != null)
                  Text(
                    '收听$count次',
                    style: TextStyle(
                      fontSize: MusicTypography.captionSize,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RankSinger extends StatelessWidget {
  const _RankSinger({required this.row});
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context) {
    final singer = kugouObject(row['singer_info']);
    final count = kugouNonnegative(row['total']);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: PlatformAvatar(url: PlatformSession.picture(singer['avatar'])),
      title: Text('${singer['name'] ?? '歌手名称暂未返回'}'),
      subtitle: count == null ? null : Text('收听$count次'),
    );
  }
}

String _periodDate(KugouListenPeriod period, DateTime date) {
  String day(DateTime value) =>
      '${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';
  return switch (period) {
    KugouListenPeriod.day => '${date.year}年 ${day(date)}',
    KugouListenPeriod.week =>
      '${date.year}年 ${day(date)}—${day(date.add(const Duration(days: 6)))}',
    KugouListenPeriod.month => '${date.year}年${date.month}月',
    KugouListenPeriod.year => '${date.year}年',
  };
}

/// 只画服务实际给出的点；缺失项断开，不把未读取资料填成零收听。
class _StatisticsChart extends StatelessWidget {
  const _StatisticsChart({required this.statistics});
  final KugouListeningStatistics statistics;
  String label(Map<String, dynamic> row, int index) =>
      switch (statistics.period) {
        KugouListenPeriod.day => '$index时',
        KugouListenPeriod.week =>
          '周${const ['一', '二', '三', '四', '五', '六', '日'][index % 7]}',
        KugouListenPeriod.month => _month('${row['month'] ?? ''}'),
        _ => '',
      };
  String _month(String text) => text.length >= 6
      ? '${text.substring(0, 4)}.${text.substring(4, 6)}'
      : '月份暂未返回';
  @override
  Widget build(BuildContext context) {
    final rows = statistics.series;
    final points = [
      for (final row in rows) kugouNonnegative(row['listen_duration']),
    ];
    final maximum = points.whereType<int>().fold<int>(0, math.max);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              statistics.period == KugouListenPeriod.month
                  ? '每月收听趋势'
                  : '收听时长分布',
              style: const TextStyle(
                fontSize: MusicTypography.bodySize,
                fontWeight: MusicTypography.titleWeight,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '最高 ${kugouDuration(maximum)}',
              style: TextStyle(
                fontSize: MusicTypography.captionSize,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ExcludeSemantics(
              child: SizedBox(
                height: 145,
                width: double.infinity,
                child: CustomPaint(
                  painter: _ListeningChartPainter(
                    points,
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Text(
                  label(rows.first, 0),
                  style: const TextStyle(
                    fontSize: MusicTypography.smallCaptionSize,
                  ),
                ),
                const Spacer(),
                Text(
                  label(rows.last, rows.length - 1),
                  style: const TextStyle(
                    fontSize: MusicTypography.smallCaptionSize,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('查看时长明细'),
              children: [
                for (var index = 0; index < rows.length; index++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Expanded(child: Text(label(rows[index], index))),
                        Flexible(
                          child: Text(
                            points[index] == null
                                ? '官方暂未返回'
                                : kugouDuration(points[index]),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
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

class _ListeningChartPainter extends CustomPainter {
  _ListeningChartPainter(this.values, this.color, this.grid);
  final List<int?> values;
  final Color color, grid;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }
    final maximum = math.max(1, values.whereType<int>().fold<int>(0, math.max));
    final lines = Paint()
      ..color = grid.withValues(alpha: .6)
      ..strokeWidth = .7;
    for (var index = 0; index <= 3; index++) {
      final y = 5 + (size.height - 10) * index / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), lines);
    }
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    var connected = false;
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      if (value == null) {
        connected = false;
        continue;
      }
      final point = Offset(
        values.length == 1
            ? size.width / 2
            : size.width * index / (values.length - 1),
        size.height - 5 - (size.height - 10) * value / maximum,
      );
      if (connected) {
        path.lineTo(point.dx, point.dy);
      } else {
        path.moveTo(point.dx, point.dy);
      }
      connected = true;
      canvas.drawCircle(point, 2.5, Paint()..color = color);
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_ListeningChartPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.grid != grid ||
      oldDelegate.values != values;
}
