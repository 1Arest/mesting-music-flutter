import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_content_insets.dart';
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
  bool _weekly = true, _busy = false;
  String? _owner, _token, _error;
  int _epoch = 0;
  List<NeteaseOfficialPlayRecord> _items = const [];
  bool get _current {
    final account = ref.read(platformAccountProvider).value;
    return ref.read(usesNeteaseProvider) &&
        account?.ownerId == _owner &&
        account?.token == _token;
  }

  @override
  void initState() {
    super.initState();
    final account = ref.read(platformAccountProvider).value;
    _owner = account?.ownerId;
    _token = account?.token;
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!_current || !mounted) return;
    final epoch = ++_epoch, weekly = _weekly;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(platformAccountProvider).value;
      if (session == null) throw StateError('请先登录网易云账号');
      final payload = await ref.read(neteaseMusicRepositoryProvider).call(
        '/user/record',
        {'uid': session.userId, 'type': weekly ? 1 : 0},
      );
      if (!mounted || !_current || epoch != _epoch) return;
      setState(
        () => _items = NeteaseOfficialPlayRecord.parse(payload, weekly: weekly),
      );
    } catch (_) {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(platformAccountProvider);
    return PlatformPageFrame(
      title: '网易云听歌排行',
      child: !_current
          ? const Center(child: Text('账号已变化，请返回后重新打开'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  BetaContentInsets.bottomOf(context, 32),
                ),
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('最近一周')),
                      ButtonSegment(value: false, label: Text('累计排行')),
                    ],
                    selected: {_weekly},
                    onSelectionChanged: (value) {
                      setState(() {
                        _weekly = value.first;
                        _items = const [];
                      });
                      _load();
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text('数据来自网易云官方听歌排行。次数与更新节奏以平台返回为准，与本机“听歌足迹”分开记录。'),
                  ),
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
                                contextTracks: _items
                                    .map((e) => e.track)
                                    .toList(),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 4,
                                  bottom: 12,
                                ),
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
            ),
    );
  }
}
