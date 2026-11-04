import '../../presentation/song_actions_sheet.dart';
import '../../../../shared/widgets/song_list_tools.dart';
import '../../../../shared/widgets/beta_page_motion.dart';
import '../../../../shared/widgets/beta_swipe_pages.dart';
import 'dart:async';
import 'dart:ui' show ImageFilter, lerpDouble;
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/track.dart';
import '../../../../shared/widgets/artwork_image.dart';
import '../../../../shared/widgets/beta_bottom_search.dart';
import '../../../../shared/widgets/beta_content_insets.dart';
import '../../../../shared/widgets/beta_edge_back.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../../../shared/widgets/beta_page_search_layout.dart';
import '../../../player/presentation/beta_playback_actions.dart';
import '../../../themes/beta_appearance.dart';
import '../../presentation/platform_design.dart';
import 'official_footprint.dart';
import 'official_footprint_page.dart';
import 'official_footprint_providers.dart';
import 'official_footprint_reader.dart';
import 'listening_footprint_chart.dart';
import 'listening_footprint_models.dart';
import 'listening_footprint_providers.dart';
import 'listening_footprint_reader.dart';

/// Apple's large-title hierarchy over the app's existing glass/music shell.
/// This page only reads official reports; diagnostics and local playback
/// bookkeeping remain separate and reachable through the final action.
class NeteaseListeningFootprintPage extends ConsumerStatefulWidget {
  const NeteaseListeningFootprintPage({super.key, this.onSongSelected});
  final Future<void> Function(OfficialFootprintSong)? onSongSelected;
  @override
  ConsumerState<NeteaseListeningFootprintPage> createState() =>
      _ListeningFootprintPageState();
}

class _ListeningFootprintPageState
    extends ConsumerState<NeteaseListeningFootprintPage>
    with WidgetsBindingObserver {
  ListeningFootprintReader? _bound;
  OfficialFootprintReader? _summary;
  Timer? _calendar;
  bool _active = true;
  String _query = '';
  final _scrolls = List.generate(3, (_) => ScrollController());
  final _scrollPageKeys = List.generate(3, (_) => GlobalKey());
  ScrollController get _scroll => _scrolls[_bound?.scale.index ?? 0];
  Drag? _headerDrag;
  double? _swipeHeaderOffset;
  int _headerSwipeGeneration = 0;
  final _selectedDays = <String, String>{};
  late final BetaPageSearchController _search;

  @override
  void initState() {
    super.initState();
    _search = BetaPageSearchController(
      hintText: '搜索今日听过的歌曲',
      onChanged: _filter,
      onSubmitted: _filter,
      onCleared: () => _filter(''),
    );
    WidgetsBinding.instance.addObserver(this);
    // Detect date rollover, not a report polling/upload loop. A hidden page
    // never refreshes account data just because its state remains mounted.
    _calendar = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_visible && _bound?.calendarChanged == true) unawaited(_refresh());
    });
  }

  bool get _visible =>
      mounted && _active && ModalRoute.of(context)?.isCurrent == true;
  void _filter(String value) {
    if (mounted) setState(() => _query = value.trim().toLowerCase());
  }

  void _startHeaderDrag(DragStartDetails details) {
    _headerDrag?.cancel();
    if (!_scroll.hasClients) return;
    // Moving the header out of the pager must not remove vertical drags that
    // start on its title. Reuse the active scroll's own physics and activity.
    _headerDrag = _scroll.position.drag(details, () => _headerDrag = null);
  }

  bool _holdHeaderDuringSwipe(ScrollNotification event) {
    if (event.depth != 0 || event.metrics.axis != Axis.horizontal) return false;
    if (event is ScrollStartNotification && event.dragDetails != null) {
      ++_headerSwipeGeneration;
      // Different pages may retain different vertical offsets. Changing the
      // active scale halfway across a swipe must not move the common title's
      // alignment or resize its header while the finger is still paging.
      _swipeHeaderOffset = _scroll.hasClients ? _scroll.offset : 0;
    } else if (event is ScrollEndNotification && _swipeHeaderOffset != null) {
      final generation = _headerSwipeGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            generation != _headerSwipeGeneration ||
            _swipeHeaderOffset == null) {
          return;
        }
        setState(() => _swipeHeaderOffset = null);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    return false;
  }

  void _revealReport() {
    if (!_scroll.hasClients) return;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final target = 116.0 + ((scale - 1) * 112).clamp(0, 160);
    if (_scroll.offset <= target) return;
    // A pinned segment can be changed while the user is far down today's
    // songs. Bring the new report's navigation directly below the toolbar;
    // otherwise the selection changes invisibly hundreds of pixels above it.
    unawaited(
      _scroll.animateTo(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _refresh() async {
    await Future.wait([
      if (_summary != null) _summary!.refreshTotalOnly(),
      if (_bound != null) _bound!.refresh(),
    ]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_visible) unawaited(_refresh());
  }

  @override
  void dispose() {
    _calendar?.cancel();
    _headerDrag?.cancel();
    _search.dispose();
    for (final scroll in _scrolls) {
      scroll.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(listeningFootprintReaderProvider);
    final summary = ref.watch(officialFootprintReaderProvider);
    if (_bound != detail || _summary != summary) {
      _bound = detail;
      _summary = summary;
      _selectedDays.clear();
      _query = '';
      _swipeHeaderOffset = null;
      ++_headerSwipeGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !identical(detail, _bound) ||
            !identical(summary, _summary)) {
          return;
        }
        _search.clearResults();
        unawaited(_refresh());
      });
    }
    return PlatformStyle(
      artworkReadiness: false,
      child: BetaPageSearchLayout(
        controller: _search,
        child: BetaEdgeBack(
          child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: AnimatedBuilder(
              animation: Listenable.merge([?detail, ?summary]),
              builder: (context, _) {
                final scale = detail?.scale ?? FootprintScale.week;
                final metrics = _FootprintHeaderMetrics(
                  top: MediaQuery.paddingOf(context).top,
                  textScale: MediaQuery.textScalerOf(context).scale(16) / 16,
                );
                final scroll = _scrolls[scale.index];
                return Stack(
                  children: [
                    Positioned.fill(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _holdHeaderDuringSwipe,
                        child: BetaSwipePages(
                          index: scale.index,
                          length: 3,
                          onChanged: (index) {
                            if (detail == null) return;
                            detail.selectScale(FootprintScale.values[index]);
                            unawaited(detail.loadSelected());
                          },
                          itemBuilder: (context, index) => _reportPage(
                            detail,
                            index,
                            headerExtent: metrics.maxExtent,
                          ),
                        ),
                      ),
                    ),
                    // One common glass header stays outside the horizontal
                    // viewport. Each scale still owns its vertical controller;
                    // only that scale can compact this shared large title.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedBuilder(
                        animation: scroll,
                        builder: (context, _) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragStart: _startHeaderDrag,
                          onVerticalDragUpdate: (details) =>
                              _headerDrag?.update(details),
                          onVerticalDragEnd: (details) =>
                              _headerDrag?.end(details),
                          onVerticalDragCancel: () => _headerDrag?.cancel(),
                          child: _FootprintHeader(
                            metrics: metrics,
                            scrollOffset:
                                _swipeHeaderOffset ??
                                (scroll.hasClients ? scroll.offset : 0),
                            scale: scale,
                            total:
                                summary?.total ?? const FootprintReading<int>(),
                            loading:
                                summary?.total.loading == true ||
                                detail?.loading == true,
                            onScale: detail == null
                                ? null
                                : (scale) {
                                    detail.selectScale(scale);
                                    _revealReport();
                                    unawaited(detail.loadSelected());
                                  },
                            onRefresh: detail == null
                                ? null
                                : () => unawaited(_refresh()),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _reportPage(
    ListeningFootprintReader? detail,
    int index, {
    required double headerExtent,
  }) {
    final pageScale = FootprintScale.values[index];
    final page = detail?.view(pageScale);
    return KeyedSubtree(
      key: index == (detail?.scale.index ?? 0)
          ? const ValueKey('listening-footprint-scroll')
          : ValueKey('footprint-scroll-$index'),
      // The active-page marker changes on a swipe. A stable identity below it
      // retains the actual scroll element/position instead of detaching and
      // recreating that page at offset zero when its marker changes.
      child: SongListTools(
        listId: 'footprint-today:$index:$_query',
        child: CustomScrollView(
          key: _scrollPageKeys[index],
          controller: _scrolls[index],
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            // A transparent spacer preserves the original report/scroll geometry
            // while the real header is painted once above all horizontal pages.
            SliverToBoxAdapter(child: SizedBox(height: headerExtent)),
            if (detail == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('请返回并选择网易云账号')),
              )
            else ...[
              SliverToBoxAdapter(child: _periodNavigation(page!)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
                  child: pageScale == FootprintScale.year
                      ? _yearReport(page)
                      : _dailyReport(page),
                ),
              ),
              ..._todaySlivers(page),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    26,
                    22,
                    BetaContentInsets.musicBottomOf(context, 32),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Footnote('网易云官方多端统计。今日数据可能延迟 1～2 分钟，历史总时长按天更新。'),
                      const SizedBox(height: 18),
                      BetaGlassButton(
                        key: const ValueKey('footprint-open-diagnostics'),
                        onPressed: () => Navigator.of(context).push(
                          MestingPageRoute<void>(
                            builder: (_) => const OfficialFootprintPage(),
                          ),
                        ),
                        child: const Text('统计与本机记录核对'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _periodNavigation(ListeningFootprintView reader) {
    final period = reader.selection;
    final first = period.civilStart,
        last = period.civilEnd.subtract(const Duration(days: 1));
    final label = switch (period.scale) {
      FootprintScale.week =>
        '${first.year}年${first.month}月${first.day}日 – ${first.month == last.month ? '' : '${last.month}月'}${last.day}日',
      FootprintScale.month => '${first.year}年${first.month}月',
      FootprintScale.year => '${first.year}年',
    };
    Widget arrow(int delta, IconData icon, String semantic) => BetaGlassButton(
      key: ValueKey(delta < 0 ? 'footprint-previous' : 'footprint-next'),
      width: 44,
      height: 44,
      label: semantic,
      onPressed: reader.canMove(delta)
          ? () {
              reader.move(delta);
              unawaited(reader.loadSelected());
            }
          : null,
      child: Icon(icon, size: 18),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        children: [
          arrow(-1, CupertinoIcons.chevron_left, '上一个区间'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                label,
                key: const ValueKey('footprint-period-label'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          arrow(1, CupertinoIcons.chevron_right, '下一个区间'),
        ],
      ),
    );
  }

  Widget _dailyReport(ListeningFootprintView reader) {
    final reading = reader.report,
        report = reading.value,
        period = reader.selection;
    if (report == null) {
      return _UnavailableReport(
        loading: reading.loading,
        message: reading.failed
            ? '所选区间暂时无法读取，报表开放时间或账号查看范围也可能影响读取。'
            : '尚未获取所选区间的数据。',
        onRetry: () => reader.loadSelected(force: true),
      );
    }
    final keys = period.dayKeys, today = footprintDay(reader.now());
    final available = keys.where(report.days.containsKey).toList();
    final selected =
        _selectedDays[period.key] ??
        (report.days.containsKey(today)
            ? today
            : (available.isEmpty ? keys.first : available.last));
    final day = report.days[selected];
    final bars = [
      for (var i = 0; i < keys.length; i++)
        FootprintChartBar(
          id: keys[i],
          label: period.scale == FootprintScale.week
              ? ['日', '一', '二', '三', '四', '五', '六'][i]
              : (i == 0 || (i + 1) % 5 == 0 || i == keys.length - 1
                    ? '${i + 1}'
                    : ''),
          caption: keys[i],
          seconds: report.days[keys[i]]?.seconds,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DurationHeadline(
          seconds: report.period.seconds,
          key: const ValueKey('footprint-period-duration'),
        ),
        const SizedBox(height: 7),
        _Footnote(
          report.listenDays == null
              ? '官方未返回收听天数'
              : '收听了 ${report.listenDays} 天',
        ),
        _ReadingStatus(reading: reading),
        const SizedBox(height: 20),
        _DaySelection(day: selected, detail: day),
        const SizedBox(height: 18),
        FootprintDurationChart(
          bars: bars,
          selected: selected,
          onSelected: (value) =>
              setState(() => _selectedDays[period.key] = value),
        ),
        if (bars.any((b) => b.seconds == null))
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: _Footnote('“—”表示官方未返回该日记录，不计作 0 分钟。'),
          ),
      ],
    );
  }

  Widget _yearReport(ListeningFootprintView reader) {
    final reading = reader.yearly, value = reading.value;
    if (value == null) {
      return _UnavailableReport(
        loading: reading.loading,
        message: reading.failed ? '年度足迹读取失败，请重试。' : '尚未获取年度足迹。',
        onRetry: () => reader.loadSelected(force: true),
      );
    }
    if (value.years.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('官方暂未返回可查看的年度足迹。'),
      );
    }
    final year = reader.selection.civilStart.year;
    final selected = value.years.firstWhere(
      (item) => item.year == year,
      orElse: () => value.years.last,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DurationHeadline(
          seconds: selected.seconds,
          key: const ValueKey('footprint-period-duration'),
        ),
        const SizedBox(height: 7),
        _Footnote('全年收听 ${selected.songCount} 首歌曲'),
        _ReadingStatus(reading: reading),
        const SizedBox(height: 24),
        Text(
          '${selected.year} 年 · ${officialDuration(selected.seconds)}',
          key: const ValueKey('footprint-selected-year'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        FootprintDurationChart(
          bars: [
            for (final item in value.years)
              FootprintChartBar(
                id: '${item.year}',
                label: '${item.year}',
                caption: '${item.year}年',
                seconds: item.seconds,
              ),
          ],
          selected: '${selected.year}',
          onSelected: (value) => reader.selectYear(int.parse(value)),
        ),
        const SizedBox(height: 12),
        const _Footnote('年度汇总按官方返回的年份展示；官方未提供月度明细。'),
      ],
    );
  }

  List<Widget> _todaySlivers(ListeningFootprintView reader) {
    final reading = reader.todaySongs, today = footprintDay(reader.now());
    final value = reading.value, oldDay = value != null && value.day != today;
    final all = value?.songs ?? const <OfficialFootprintSong>[];
    final songs = all
        .where(
          (song) =>
              _query.isEmpty ||
              '${song.title} ${song.alias} ${song.artists.join(' ')}'
                  .toLowerCase()
                  .contains(_query),
        )
        .toList();
    final tracks = songs
        .map(
          (song) => Track(
            id: 'netease_${song.id}',
            title: song.title,
            artist: song.artists.join(' / '),
            album: '',
            duration: Duration.zero,
            audioAsset: 'mesting-platform://netease/${song.id}',
            coverAsset: song.cover,
            lyricsAsset: '',
            source: TrackSource.netease,
            provider: '网易云音乐',
            platformSongId: song.id,
          ),
        )
        .toList();
    final todayBlock = oldDay ? null : reader.todayListening;
    final covers =
        (todayBlock?.covers.isNotEmpty == true
                ? todayBlock!.covers
                : all.map((s) => s.cover).where((s) => s.isNotEmpty))
            .toSet()
            .take(5)
            .toList();
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 34, 22, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                oldDay ? '上次听歌记录 · ${value.day}' : '今日听过',
                key: const ValueKey('footprint-today-title'),
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.4,
                ),
              ),
              const SizedBox(height: 7),
              _Footnote(
                todayBlock?.songCount != null
                    ? '今天收听了 ${todayBlock!.songCount} 首歌曲'
                    : '仅展示${oldDay ? '当日' : '今日'}最近收听的 100 首歌曲',
              ),
              if (!reader.selection.isCurrent(reader.now()) && !oldDay)
                const Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: _Footnote('以下为今日记录，与上方历史区间分开展示。'),
                ),
              _ReadingStatus(reading: reading),
              if (covers.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    for (var i = 0; i < covers.length; i++) ...[
                      if (i > 0) const SizedBox(width: 9),
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: ArtworkImage(
                              uri: covers[i],
                              decodeWidth: 80,
                              decodeHeight: 80,
                            ),
                          ),
                        ),
                      ),
                    ],
                    for (var i = covers.length; i < 5; i++) ...[
                      const SizedBox(width: 9),
                      const Expanded(child: SizedBox.shrink()),
                    ],
                  ],
                ),
              ],
              if (_query.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    '找到 ${songs.length} 首歌曲',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              if (value == null)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: _UnavailableReport(
                    loading: reading.loading,
                    message: reading.failed ? '今日歌曲读取失败。' : '尚未获取今日歌曲。',
                    onRetry: () => reader.loadToday(force: true),
                  ),
                )
              else if (songs.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(
                    _query.isEmpty ? '官方尚未记录今天听过的歌曲。' : '没有符合搜索条件的今日歌曲。',
                  ),
                ),
            ],
          ),
        ),
      ),
      SliverList.builder(
        itemCount: songs.length,
        itemBuilder: (context, index) => SongListEntry(
          track: tracks[index],
          tracks: tracks,
          child: _TodaySongRow(
            song: songs[index],
            track: tracks[index],
            onTap: () async {
              // A retained prior-day row remains an honest song entry. Selecting
              // it starts only that song via the app's normal playback owner.
              final song = songs[index];
              SongListTools.remember(context, tracks[index]);
              if (widget.onSongSelected != null) {
                await widget.onSongSelected!(song);
              } else {
                await playBetaSelection(context, ref, tracks[index]);
              }
            },
          ),
        ),
      ),
    ];
  }
}

/// Shared geometry keeps large-text spacing and the body's scroll reservation
/// identical without making the header part of any horizontal page.
class _FootprintHeaderMetrics {
  const _FootprintHeaderMetrics({required this.top, required this.textScale});
  final double top, textScale;
  double get segmentHeight => 44 + ((textScale - 1) * 24).clamp(0, 32);
  double get minExtent => top + 68 + segmentHeight;
  double get maxExtent =>
      minExtent + 116 + ((textScale - 1) * 112).clamp(0, 160);
}

class _FootprintHeader extends StatelessWidget {
  const _FootprintHeader({
    required this.metrics,
    required this.scrollOffset,
    required this.scale,
    required this.total,
    required this.loading,
    required this.onScale,
    required this.onRefresh,
  });
  final _FootprintHeaderMetrics metrics;
  final double scrollOffset;
  final FootprintScale scale;
  final FootprintReading<int> total;
  final bool loading;
  final ValueChanged<FootprintScale>? onScale;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final top = metrics.top, textScale = metrics.textScale;
    final collapse = scrollOffset.clamp(
      0.0,
      metrics.maxExtent - metrics.minExtent,
    );
    final t = collapse / (metrics.maxExtent - metrics.minExtent);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: const ValueKey('footprint-shared-header'),
      height: metrics.maxExtent - collapse,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: ColoredBox(
            color: scheme.surface.withValues(alpha: .94),
            child: Stack(
              children: [
                Positioned(
                  top: top + 6,
                  left: 18,
                  child: const BetaGlassBackButton(),
                ),
                Positioned(
                  top: top + 6,
                  right: 18,
                  child: BetaGlassButton(
                    key: const ValueKey('listening-footprint-refresh'),
                    width: 48,
                    height: 48,
                    label: '刷新听歌足迹',
                    loading: loading,
                    onPressed: onRefresh,
                    child: const Icon(CupertinoIcons.arrow_clockwise, size: 21),
                  ),
                ),
                Positioned(
                  left: 22,
                  right: 22,
                  top: lerpDouble(top + 71, top + 18, t),
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment(lerpDouble(-1, 0, t)!, 0),
                      child: Text(
                        '听歌足迹',
                        key: const ValueKey('footprint-collapsing-title'),
                        style: TextStyle(
                          fontSize: lerpDouble(34, 17, t),
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          letterSpacing: lerpDouble(-.9, -.2, t),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 22,
                  right: 22,
                  top: top + 119 + ((textScale - 1) * 42).clamp(0, 60) - 44 * t,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (1 - t * 1.65).clamp(0, 1),
                      child: ExcludeSemantics(
                        excluding: t > .6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              total.value == null
                                  ? '官方累计时长暂未获取'
                                  : '累计听歌 ${officialDuration(total.value!)}',
                              key: const ValueKey('footprint-official-total'),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (total.failed)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  total.value == null
                                      ? '读取失败，点击右上角重试'
                                      : '刷新失败，保留上次官方读数',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 22,
                  right: 22,
                  bottom: 10,
                  child: SizedBox(
                    height: metrics.segmentHeight,
                    child: CupertinoSlidingSegmentedControl<FootprintScale>(
                      key: const ValueKey('footprint-scale-control'),
                      groupValue: scale,
                      backgroundColor: BetaAppearance.panel(
                        Theme.of(context).brightness,
                      ),
                      thumbColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? scheme.surfaceContainerHighest
                          : Colors.white,
                      proportionalWidth: false,
                      onValueChanged: (value) {
                        if (value != null) onScale?.call(value);
                      },
                      children: {
                        for (final value in FootprintScale.values)
                          value: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 5,
                            ),
                            child: Text(
                              switch (value) {
                                FootprintScale.week => '周',
                                FootprintScale.month => '月',
                                FootprintScale.year => '年',
                              },
                              key: ValueKey('footprint-scale-${value.name}'),
                              style: TextStyle(
                                fontSize: 14,
                                color: scheme.onSurface,
                                fontWeight: scale == value
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                      },
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
}

class _DaySelection extends StatelessWidget {
  const _DaySelection({required this.day, required this.detail});
  final String day;
  final OfficialFootprintDay? detail;
  @override
  Widget build(BuildContext context) {
    final d = DateTime.parse(day), value = detail;
    return Semantics(
      liveRegion: true,
      child: Column(
        key: const ValueKey('footprint-selected-day'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${d.month}月${d.day}日 · 周${['一', '二', '三', '四', '五', '六', '日'][d.weekday - 1]}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            value == null ? '官方未返回这一天的数据' : officialDuration(value.seconds),
            style: TextStyle(
              fontSize: value == null ? 15 : 23,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (value != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: _Footnote(
                [
                  if (value.songSeconds > 0 || value.seconds == 0)
                    '歌曲 ${officialDuration(value.songSeconds)}',
                  if (value.podcastSeconds > 0)
                    '播客 ${officialDuration(value.podcastSeconds)}',
                  if (value.audiobookSeconds > 0)
                    '有声书 ${officialDuration(value.audiobookSeconds)}',
                ].join(' · '),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadingStatus extends StatelessWidget {
  const _ReadingStatus({required this.reading});
  final FootprintReading<Object> reading;
  @override
  Widget build(BuildContext context) {
    final at = reading.readAt;
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: _Footnote(
        [
          if (reading.failed)
            reading.value == null ? '读取失败，可重试' : '刷新失败，保留上次成功数据',
          if (reading.loading) '正在读取官方数据…',
          if (at != null) '更新于 ${footprintDay(at)} ${_clock(at)}',
        ].join(' · '),
      ),
    );
  }
}

String _clock(DateTime time) {
  final d = footprintDate(time);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Smaller units preserve a readable metric at large text sizes without
/// shrinking the user's chosen numeral size or orphaning the last CJK glyph.
class _DurationHeadline extends StatelessWidget {
  const _DurationHeadline({required this.seconds, super.key});
  final int seconds;
  @override
  Widget build(BuildContext context) {
    final h = seconds ~/ 3600, m = seconds % 3600 ~/ 60;
    const units = TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );
    return Text.rich(
      TextSpan(
        children: [
          if (h > 0) ...[
            TextSpan(text: '$h'),
            const TextSpan(text: ' 小时 ', style: units),
          ],
          TextSpan(text: '$m'),
          const TextSpan(text: ' 分钟', style: units),
        ],
      ),
      style: const TextStyle(
        fontSize: 30,
        height: 1.3,
        fontWeight: FontWeight.w800,
        letterSpacing: -.6,
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      height: 1.5,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _UnavailableReport extends StatelessWidget {
  const _UnavailableReport({
    required this.loading,
    required this.message,
    required this.onRetry,
  });
  final bool loading;
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          loading ? '正在读取官方数据…' : message,
          style: const TextStyle(fontSize: 15, height: 1.6),
        ),
        if (!loading) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: BetaGlassButton(
              onPressed: onRetry,
              child: const Text('重新读取'),
            ),
          ),
        ],
      ],
    ),
  );
}

class _TodaySongRow extends StatelessWidget {
  const _TodaySongRow({
    required this.song,
    required this.track,
    required this.onTap,
  });
  final Track track;
  final OfficialFootprintSong song;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label:
        '${song.title}，${song.artists.join('、')}，${_clock(song.lastPlayedAt)}听过，播放歌曲',
    child: CupertinoButton(
      key: ValueKey('footprint-song-${song.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
      onPressed: onTap,
      // Keep the new independent menu target exposed to assistive services.
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: ArtworkImage(
              uri: song.cover,
              width: 52,
              height: 52,
              decodeWidth: 80,
              decodeHeight: 80,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  song.artists.join(' / '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SongActionsButton(track: track),
          const SizedBox(width: 10),
          Text(
            _clock(song.lastPlayedAt),
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}
