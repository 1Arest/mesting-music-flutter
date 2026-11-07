import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'player_more_menu.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../history/listening_replay.dart';
import '../../music_platform/presentation/platform_design.dart';
import '../../themes/music_theme_tokens.dart';
import 'editorial_widgets.dart';
import '../../../shared/widgets/artwork_image.dart';

class ListeningReplayPage extends ConsumerStatefulWidget {
  const ListeningReplayPage({super.key});
  @override
  ConsumerState<ListeningReplayPage> createState() =>
      _ListeningReplayPageState();
}

class _ListeningReplayPageState extends ConsumerState<ListeningReplayPage> {
  int _year = DateTime.now().year;
  int? _month = DateTime.now().month;
  final _selectedMonth = GlobalKey();
  bool _revealPending = true;
  @override
  Widget build(BuildContext context) {
    final days = ref.watch(playbackDaysProvider);
    final today = DateTime.now();
    if (_revealPending) {
      _revealPending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _selectedMonth.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            alignment: .5,
            duration: Duration.zero,
          );
        }
      });
    }
    final years = <int>{
      DateTime.now().year,
      _year,
      for (final day in days.value ?? [])
        if (day.dayKey.length >= 4)
          if ((int.tryParse(day.dayKey.substring(0, 4)) ?? today.year) <=
              today.year)
            int.tryParse(day.dayKey.substring(0, 4)) ?? today.year,
    }.toList()..sort((a, b) => b.compareTo(a));
    return PlatformStyle(
      child: _ReplayAtmosphere(
        cover:
            ListeningReplay.fromDays(
              days.value ?? [],
              _year,
              _month,
            ).tracks.firstOrNull?.track.coverAsset ??
            '',
        child: EditorialScroll(
          children: [
            EditorialHeader(
              '听歌回顾',
              back: true,
              trailing: PlayerMoreMenu(
                tooltip: '选择年份',
                menuWidth: 168,
                groups: [
                  [
                    for (final year in years)
                      PlayerMenuAction(
                        '$year',
                        '$year 年',
                        CupertinoIcons.calendar,
                        selected: year == _year,
                      ),
                  ],
                ],
                onSelected: (value) => setState(() {
                  _year = int.parse(value);
                  // Returning from December of a past year cannot select a
                  // month that has not happened in the current year.
                  if (_year == today.year && (_month ?? 0) > today.month) {
                    _month = today.month;
                  }
                  _revealPending = true;
                }),
                trigger: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_year',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 56,
              // All available chips must exist before reveal; a lazy list
              // cannot locate an initially off-screen selected month.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    for (final month in replayMonthsForYear(_year, today))
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(month == null ? '全年' : '$month 月'),
                          selected: _month == month,
                          key: _month == month ? _selectedMonth : null,
                          onSelected: (_) => setState(() {
                            _month = month;
                            _revealPending = true;
                          }),
                          showCheckmark: false,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            days.when(
              loading: () => const PlatformFeedbackState(loading: true),
              error: (_, _) => EditorialEmpty(
                '听歌记录暂时无法读取',
                onRetry: () => ref.invalidate(playbackDaysProvider),
              ),
              data: (records) {
                final replay = ListeningReplay.fromDays(records, _year, _month);
                final tracks = replay.tracks.map((e) => e.track).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 36, 22, 8),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _month == null
                                  ? '这一年，你听了\n'
                                  : '$_month 月，你听了\n',
                              style: TextStyle(
                                color: context.musicThemeTokens.textSecondary,
                              ),
                            ),
                            TextSpan(
                              text: '${replay.milliseconds ~/ 60000} 分钟',
                              style: TextStyle(
                                color: context.musicThemeTokens.textPrimary,
                              ),
                            ),
                            TextSpan(
                              text: '的音乐。',
                              style: TextStyle(
                                color: context.musicThemeTokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        style: const TextStyle(
                          fontSize: 34,
                          height: 1.4,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.8,
                        ),
                      ),
                    ),
                    if (records.isEmpty || replay.tracks.isEmpty)
                      const EditorialEmpty('这个时段还没有听歌记录。\n从现在开始播放，回顾会逐渐丰富。')
                    else ...[
                      const EditorialSection('常听歌手'),
                      EditorialShelf(
                        height: 308,
                        children: [
                          for (final (index, artist)
                              in replay.artists.take(10).indexed)
                            EditorialCover(
                              cover: artist.cover,
                              title: artist.name,
                              rank: index + 1,
                              subtitle:
                                  '${artist.milliseconds ~/ 60000} 分钟 · 歌曲封面',
                              width: 238,
                              height: 294,
                              feature: true,
                              onTap: () => playEditorialTrack(
                                context,
                                ref,
                                replay.tracks
                                    .firstWhere(
                                      (e) =>
                                          e.track.artist.trim() == artist.name,
                                    )
                                    .track,
                                tracks,
                              ),
                            ),
                        ],
                      ),
                      const EditorialSection('反复聆听'),
                      for (final (index, item)
                          in replay.tracks.take(30).indexed)
                        EditorialTrackRow(
                          track: item.track,
                          contextTracks: tracks,
                          rank: index + 1,
                        ),
                    ],
                    Padding(
                      padding: const EdgeInsets.all(22),
                      child: Text(
                        '根据当前账号在本机保存的每日记录统计。未记录的过去时段不会补算。',
                        style: TextStyle(
                          color: context.musicThemeTokens.textSecondary,
                          fontSize: 12,
                          height: 1.7,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The actual listened cover supplies atmosphere, never an invented artist photo.
class _ReplayAtmosphere extends StatelessWidget {
  const _ReplayAtmosphere({required this.cover, required this.child});
  final String cover;
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      if (cover.isNotEmpty)
        Positioned(
          top: -110,
          right: -110,
          width: 440,
          height: 440,
          child: IgnorePointer(
            child: Opacity(
              opacity: Theme.of(context).brightness == Brightness.dark
                  ? .28
                  : .32,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 65, sigmaY: 65),
                child: ArtworkImage(uri: cover, width: 440, height: 440),
              ),
            ),
          ),
        ),
      child,
    ],
  );
}
