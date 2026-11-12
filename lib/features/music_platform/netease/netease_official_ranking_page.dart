import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_swipe_pages.dart';
import '../../experience/presentation/editorial_widgets.dart';
import '../music_platform_providers.dart';
import '../platform_backend_providers.dart';
import '../presentation/platform_design.dart';
import 'netease_music_repository.dart';

class NeteaseOfficialPlayRecord {
  const NeteaseOfficialPlayRecord(this.track, this.count);
  final Track track;
  final int? count;
  static List<NeteaseOfficialPlayRecord> parse(
    Map<String, dynamic> payload, {
    required bool weekly,
  }) {
    final result = <NeteaseOfficialPlayRecord>[];
    for (final item in NeteaseMusicRepository.rows(
      payload[weekly ? 'weekData' : 'allData'],
    )) {
      if (item['song'] is! Map) continue;
      final track = NeteaseMusicRepository.track(
        Map<String, dynamic>.from(item['song'] as Map),
      );
      if (track == null) continue;
      result.add(
        NeteaseOfficialPlayRecord(track, int.tryParse('${item['playCount']}')),
      );
    }
    return result;
  }
}

class NeteaseOfficialRankingPage extends ConsumerStatefulWidget {
  const NeteaseOfficialRankingPage({super.key});
  @override
  ConsumerState<NeteaseOfficialRankingPage> createState() =>
      _NeteaseOfficialRankingPageState();
}

class _NeteaseOfficialRankingPageState
    extends ConsumerState<NeteaseOfficialRankingPage> {
  int _period = 0;
  String? _owner, _token;

  @override
  void initState() {
    super.initState();
    final account = ref.read(platformAccountProvider).value;
    _owner = account?.ownerId;
    _token = account?.token;
  }

  void _selectPeriod(int period) {
    if (_period != period) setState(() => _period = period);
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(platformAccountProvider).value;
    final current =
        ref.watch(usesNeteaseProvider) &&
        account != null &&
        account.ownerId == _owner &&
        account.token == _token;
    return PlatformPageFrame(
      title: '网易云听歌排行',
      child: !current
          ? const Center(child: Text('账号已变化，请返回后重新打开'))
          : Column(
              children: [
                // Reuse the download manager's control, spacing and pager;
                // the heading stays fixed while only the ranking slides.
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
                  child: CupertinoSlidingSegmentedControl<int>(
                    groupValue: _period,
                    children: const {
                      0: Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('最近一周'),
                      ),
                      1: Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('累计排行'),
                      ),
                    },
                    onValueChanged: (value) {
                      if (value != null) _selectPeriod(value);
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(22, 0, 22, 12),
                  child: Text('数据来自网易云官方听歌排行。次数与更新节奏以平台返回为准，与本机“听歌足迹”分开记录。'),
                ),
                Expanded(
                  child: BetaSwipePages(
                    index: _period,
                    length: 2,
                    onChanged: _selectPeriod,
                    itemBuilder: (context, index) => _OfficialRankingPeriod(
                      key: ValueKey(index),
                      weekly: index == 0,
                      owner: _owner!,
                      token: _token!,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Each retained period owns its rows, scroll position and request revision.
/// Switching tabs cannot make a late response replace the other period.
class _OfficialRankingPeriod extends ConsumerStatefulWidget {
  const _OfficialRankingPeriod({
    required this.weekly,
    required this.owner,
    required this.token,
    super.key,
  });

  final bool weekly;
  final String owner, token;

  @override
  ConsumerState<_OfficialRankingPeriod> createState() =>
      _OfficialRankingPeriodState();
}

class _OfficialRankingPeriodState
    extends ConsumerState<_OfficialRankingPeriod> {
  final _scroll = ScrollController();
  bool _busy = false;
  String? _error;
  int _epoch = 0;
  List<NeteaseOfficialPlayRecord> _items = const [];

  bool get _current {
    final account = ref.read(platformAccountProvider).value;
    return ref.read(usesNeteaseProvider) &&
        account?.ownerId == widget.owner &&
        account?.token == widget.token;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!mounted || !_current) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = ref.read(platformAccountProvider).value!;
      final payload = await ref.read(neteaseMusicRepositoryProvider).call(
        '/user/record',
        {'uid': account.userId, 'type': widget.weekly ? 1 : 0},
      );
      if (!mounted || !_current || epoch != _epoch) return;
      setState(
        () => _items = NeteaseOfficialPlayRecord.parse(
          payload,
          weekly: widget.weekly,
        ),
      );
    } on Object {
      if (mounted && _current && epoch == _epoch) {
        setState(() => _error = '官方排行暂时无法加载，请检查登录状态或稍后重试。');
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _epoch++;
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _items.map((row) => row.track).toList(growable: false);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: ValueKey(
          widget.weekly ? 'official-ranking-week' : 'official-ranking-all',
        ),
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          BetaContentInsets.bottomOf(context, 32),
        ),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('重新加载')),
          ],
          if (!_busy && _error == null && _items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('暂无官方听歌排行，或该账号未公开这项记录。'),
            ),
          for (var i = 0; i < _items.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${i + 1}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EditorialTrackRow(
                        track: _items[i].track,
                        contextTracks: tracks,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 12),
                        child: Text(
                          _items[i].count == null
                              ? '平台未提供播放次数'
                              : '播放 ${_items[i].count} 次',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
