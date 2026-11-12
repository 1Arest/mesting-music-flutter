import '../../../../shared/widgets/beta_page_motion.dart';
import '../../presentation/platform_lazy_list.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform/share_bridge.dart';
import '../../../../shared/widgets/artwork_image.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../../../shared/widgets/beta_glass_action.dart';
import '../../presentation/platform_design.dart';
import '../full/netease_entity_picker.dart';
import '../messages/netease_messages_page.dart';
import '../messages/netease_messages_repository.dart';
import '../netease_music_repository.dart';
import 'netease_together_page.dart';
import 'together_record.dart';
import 'together_records_repository.dart';
import '../../../themes/music_typography.dart';

/// Ended-session statistics have their own clock and identity. No part of this
/// UI subscribes to the current room or adds elapsed local playback to a report.
String togetherRecordDuration(Duration? value) {
  if (value == null) return '暂未提供';
  if (value.inHours > 0) {
    return '${value.inHours}小时${value.inMinutes.remainder(60)}分钟';
  }
  if (value.inMinutes > 0) return '${value.inMinutes}分钟';
  return '${value.inSeconds}秒';
}

String _name(NeteaseTogetherProfile? person) =>
    person?.name.isNotEmpty == true ? person!.name : '网易云好友';
String _count(int? value) => value == null ? '暂未提供' : '$value首歌曲';
String _date(DateTime? value) => value == null
    ? ''
    : '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';
NeteasePerson _person(NeteaseTogetherProfile profile) =>
    NeteasePerson(profile.id, _name(profile), profile.avatar);

Future<T?> _open<T>(BuildContext context, Widget page) => Navigator.of(
  context,
  rootNavigator: true,
).push<T>(MestingPageRoute(builder: (_) => page));

class NeteaseTogetherRecordPage extends ConsumerStatefulWidget {
  const NeteaseTogetherRecordPage({
    required this.roomId,
    this.peer,
    this.initialRecord,
    this.messageTime,
    super.key,
  });
  final String roomId;
  final NeteaseTogetherProfile? peer;
  final NeteaseTogetherRecord? initialRecord;
  final DateTime? messageTime;
  @override
  ConsumerState<NeteaseTogetherRecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<NeteaseTogetherRecordPage> {
  late final _repository = ref.read(neteaseTogetherRecordsRepositoryProvider);
  NeteaseTogetherRecord? _record;
  bool _busy = false, _collecting = false, _sharing = false;
  String? _error, _actionStatus;

  bool get _current {
    if (!mounted) return false;
    try {
      _repository.checkOwner();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    // A history row is useful while loading but cannot supply report totals.
    _record = widget.initialRecord;
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!_current || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _repository.report(
        widget.roomId,
        peerId: widget.peer?.id.isNotEmpty == true ? widget.peer!.id : null,
      );
      if (_current) setState(() => _record = result);
    } catch (error) {
      if (_current) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (!_current || _record == null || _sharing) return;
    final record = _record!;
    setState(() {
      _sharing = true;
      _actionStatus = null;
    });
    try {
      final url = Uri.https(
        'mp.music.163.com',
        '/5fbcd6a217aef81f3a03eda5/ending/index.html',
        {'roomId': widget.roomId},
      );
      await ShareBridge.shareText(
        '我和${_name(record.peer ?? widget.peer)}的一起听记录\n'
        '本次陪伴 ${togetherRecordDuration(record.duration)} · ${_count(record.songCount)}\n'
        '累计 ${togetherRecordDuration(record.totalDuration)} · ${_count(record.totalSongCount)}\n$url',
        title: '分享一起听报告',
      );
    } catch (_) {
      if (_current) setState(() => _actionStatus = '分享面板暂时无法打开，请稍后重试');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _collect() async {
    if (!_current || _collecting) return;
    setState(() {
      _collecting = true;
      _actionStatus = null;
    });
    try {
      final ids = await _repository.songIds(widget.roomId);
      if (!mounted || !_current) return;
      if (ids.isEmpty) {
        setState(() => _actionStatus = '这次记录没有可收藏的歌曲');
        return;
      }
      final picked = await _open<NeteasePickedEntity>(
        context,
        const NeteaseEntityPicker(kind: 'playlist', includeDetails: true),
      );
      if (!_current || picked == null) return;
      // The generic picker includes public playlists. Verify ownership before
      // a deliberate, single batch write; opening/reading reports never writes.
      final detail = await _repository.music.call('/playlist/detail', {
        'id': picked.id,
      });
      _repository.checkOwner();
      final playlist = NeteaseMusicRepository.object(detail['playlist']);
      final creator = NeteaseMusicRepository.object(playlist['creator']);
      if ('${creator['userId']}' != _repository.music.api.session?.userId ||
          playlist['specialType'] == 5) {
        setState(() => _actionStatus = '请选择自己创建的普通歌单');
        return;
      }
      final result = await _repository.music.call('/playlist/tracks', {
        'id': picked.id,
        'op': 'add',
        'ids': ids,
      });
      _repository.checkOwner();
      if ('${result['code']}' != '200') {
        setState(() => _actionStatus = '收藏结果未确认，请到歌单中核对后再操作');
      } else {
        setState(() => _actionStatus = '已添加到「${picked.name}」');
      }
    } catch (error) {
      if (_current) setState(() => _actionStatus = '$error');
    } finally {
      if (mounted) setState(() => _collecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(neteaseTogetherRecordsRepositoryProvider);
    if (!_current) return const _AccountChanged();
    final record = _record;
    final peer = record?.peer ?? widget.peer;
    final canAct = peer?.id.isNotEmpty == true;
    final compactHeader =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(18) > 22;
    return PlatformPageFrame(
      title: '和TA的一起听',
      centerTitle: true,
      titleFontSize: compactHeader ? 16 : 18,
      musicChrome: false,
      pageKey: const ValueKey('together-record-page'),
      actions: [
        if (compactHeader)
          BetaGlassAction(
            key: const ValueKey('together-all-records'),
            label: '全部记录',
            icon: CupertinoIcons.list_bullet,
            blue: false,
            onPressed: () =>
                _open<void>(context, const NeteaseTogetherHistoryPage()),
          )
        else
          BetaGlassButton(
            key: const ValueKey('together-all-records'),
            height: 44,
            horizontalPadding: 12,
            onPressed: () =>
                _open<void>(context, const NeteaseTogetherHistoryPage()),
            child: const Text('全部记录'),
          ),
      ],
      child: record == null
          ? _RecordState(busy: _busy, error: _error, retry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                PlatformPanel(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _Avatar(peer, size: 64),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _name(peer),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 6),
                                Text(switch (record.online ?? peer?.online) {
                                  true => '在线',
                                  false => '离线',
                                  _ => '在线状态暂未获取',
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          BetaGlassButton(
                            onPressed: canAct
                                ? () => _open<void>(
                                    context,
                                    NeteaseChatPage(peer: _person(peer!)),
                                  )
                                : null,
                            child: const Text('聊天'),
                          ),
                          BetaGlassButton(
                            onPressed: canAct && record.canInvite != false
                                ? () => _open<void>(
                                    context,
                                    NeteaseTogetherPage(
                                      invitee: _person(peer!),
                                    ),
                                  )
                                : null,
                            child: const Text('再次邀请'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _ReportPanel(
                  record: record,
                  peer: peer,
                  date: record.endedAt ?? widget.messageTime,
                  collecting: _collecting,
                  sharing: _sharing,
                  collect: record.showCollectButton == true ? _collect : null,
                  share: _share,
                ),
                if (_actionStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _actionStatus!,
                      key: const ValueKey('together-action-status'),
                    ),
                  ),
                if (_error != null || _busy)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _RecordState(
                      busy: _busy,
                      error: _error,
                      retry: _load,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ReportPanel extends StatelessWidget {
  const _ReportPanel({
    required this.record,
    required this.peer,
    this.date,
    required this.collecting,
    required this.sharing,
    this.collect,
    required this.share,
  });
  final NeteaseTogetherRecord record;
  final NeteaseTogetherProfile? peer;
  final DateTime? date;
  final bool collecting, sharing;
  final VoidCallback? collect;
  final VoidCallback share;
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('together-report-panel'),
    decoration: BoxDecoration(
      color: const Color(0xFFC72C43),
      borderRadius: BorderRadius.circular(24),
    ),
    padding: const EdgeInsets.all(20),
    child: Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '一起听',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: MusicTypography.bodySize,
                  fontWeight: MusicTypography.titleWeight,
                ),
              ),
            ),
            Text(_date(date), style: const TextStyle(color: Colors.white)),
          ],
        ),
        const SizedBox(height: 26),
        _AvatarPair(self: record.self, peer: peer),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              color: Color(0xFF9D2137),
              fontSize: MusicTypography.subheadlineSize,
              height: 1.5,
            ),
            child: Column(
              children: [
                Text(
                  record.distanceKilometres == null
                      ? '距离暂未提供'
                      : record.distanceKilometres! <= .1
                      ? '我们近在彼此身边'
                      : '我们相距${record.distanceKilometres!.toStringAsFixed(2)}公里',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final metrics = [
                      _ReportMetric(
                        label: '本次一起听了',
                        value: _count(record.songCount),
                      ),
                      _ReportMetric(
                        label: '本次陪伴彼此',
                        value: togetherRecordDuration(record.duration),
                      ),
                    ];
                    return constraints.maxWidth < 240 ||
                            MediaQuery.textScalerOf(context).scale(16) > 20
                        ? Column(
                            children: [
                              metrics[0],
                              const SizedBox(height: 20),
                              metrics[1],
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: metrics[0]),
                              const SizedBox(width: 16),
                              Expanded(child: metrics[1]),
                            ],
                          );
                  },
                ),
                if (collect != null) ...[
                  const SizedBox(height: 20),
                  // Keep the normal clear glass button, with a readable light-theme
                  // foreground on the intentionally white report in either mode.
                  Theme(
                    data: Theme.of(context).copyWith(
                      brightness: Brightness.light,
                      colorScheme: ColorScheme.fromSeed(
                        seedColor: const Color(0xFFC72C43),
                      ),
                    ),
                    child: BetaGlassButton(
                      key: const ValueKey('together-collect-songs'),
                      loading: collecting,
                      onPressed: collect,
                      child: const Text('收藏到歌单'),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                const Divider(color: Color(0xFFE7C9CD)),
                const SizedBox(height: 18),
                Text(
                  '累计 ${_count(record.totalSongCount)}\n${togetherRecordDuration(record.totalDuration)}',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        BetaGlassButton(
          key: const ValueKey('together-share-report'),
          loading: sharing,
          onPressed: share,
          child: const Text('分享报告', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, textAlign: TextAlign.center),
      const SizedBox(height: 7),
      Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: MusicTypography.sectionTitleSize,
          fontWeight: MusicTypography.titleWeight,
        ),
      ),
    ],
  );
}

class NeteaseTogetherHistoryPage extends ConsumerStatefulWidget {
  const NeteaseTogetherHistoryPage({this.peer, super.key});
  final NeteaseTogetherProfile? peer;
  @override
  ConsumerState<NeteaseTogetherHistoryPage> createState() =>
      _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<NeteaseTogetherHistoryPage> {
  late final _repository = ref.read(neteaseTogetherRecordsRepositoryProvider);
  final _records = <NeteaseTogetherRecord>[];
  // Group labels are small data, not a prebuilt Widget per historical record.
  final _dateHeadings = <String?>[];
  String? _lastHistoryDate;
  final _seen = <String>{};
  NeteaseTogetherHistoryPageData? _page;
  String? _error, _cursor;
  bool _busy = false, _more = false, _masked = false;
  bool get _current {
    if (!mounted) return false;
    try {
      _repository.checkOwner();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load({bool reset = false}) async {
    if (!_current || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cursor = reset ? null : _cursor;
      final data = await _repository.history(cursor: cursor);
      if (!_current) return;
      setState(() {
        if (reset) {
          _records.clear();
          _dateHeadings.clear();
          _lastHistoryDate = null;
          _seen.clear();
          _masked = false;
        }
        _page = data;
        // Match the official account boundary. A hidden non-member row never
        // receives a tappable route; pagination cannot reveal its details.
        final visible = data.membershipLimited && data.records.isNotEmpty
            ? data.records.take(data.records.length - 1)
            : data.records;
        for (final row in visible) {
          final key = row.id.isNotEmpty
              ? row.id
              : '${row.roomId}:${row.startedAt}';
          if (_seen.add(key)) {
            _records.add(row);
            final date = row.dateLabel.isNotEmpty
                ? row.dateLabel
                : _date(row.startedAt);
            final heading = date.isNotEmpty && date != _lastHistoryDate
                ? date
                : null;
            _dateHeadings.add(heading);
            if (heading != null) _lastHistoryDate = heading;
          }
        }
        _masked |= data.membershipLimited && data.records.isNotEmpty;
        _more =
            data.hasMore == true &&
            data.nextCursor?.isNotEmpty == true &&
            data.nextCursor != cursor &&
            !data.membershipLimited;
        _cursor = data.nextCursor;
      });
    } catch (error) {
      if (_current) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(neteaseTogetherRecordsRepositoryProvider);
    if (!_current) return const _AccountChanged();
    final most = _page?.mostListened;
    return PlatformPageFrame(
      title: '一起听记录',
      musicChrome: false,
      pageKey: const ValueKey('together-history-page'),
      actions: [
        BetaGlassAction(
          label: '刷新记录',
          icon: CupertinoIcons.refresh,
          loading: _busy,
          blue: false,
          onPressed: () => _load(reset: true),
        ),
      ],
      child: _page == null
          ? _RecordState(busy: _busy, error: _error, retry: _load)
          : buildPlatformLazyList(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              header: [
                if (most != null) ...[
                  Text(
                    '和TA最常一起听',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  PlatformPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AvatarPair(self: most.self, peer: most.peer),
                        const SizedBox(height: 14),
                        Text(
                          '你和${_name(most.peer)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _page!.membershipLimited
                              ? '陪伴时长及歌曲数需网易云会员权益'
                              : '${togetherRecordDuration(most.totalDuration)} · ${_count(most.totalSongCount)}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
                Text('一起听历史', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                if (_records.isEmpty && !_masked)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Text('暂无一起听记录'),
                  ),
              ],
              itemCount: _records.length,
              itemBuilder: _historyRow,
              footer: [
                if (_masked || _page!.membershipLimited)
                  Padding(
                    key: const ValueKey('together-history-membership-limit'),
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '其余记录受网易云账号权益限制，请在网易云中查看。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                if (_error != null)
                  _RecordState(busy: false, error: _error, retry: _load),
                if (_more || _busy)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: BetaGlassButton(
                      key: const ValueKey('together-history-more'),
                      loading: _busy,
                      onPressed: _load,
                      child: const Text('加载更多记录'),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _historyRow(BuildContext context, int index) {
    final record = _records[index];
    final heading = _dateHeadings[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
            child: Text(heading, style: Theme.of(context).textTheme.titleSmall),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: ValueKey('together-history-record-${record.id}'),
              contentPadding: const EdgeInsets.all(16),
              leading: _Avatar(record.peer, size: 48),
              title: Text(_name(record.peer)),
              subtitle: Text(
                record.isMultiRoom
                    ? '多人一起听记录，请在网易云查看'
                    : '${togetherRecordDuration(record.duration)} · ${_count(record.songCount)}',
              ),
              trailing: record.isMultiRoom || record.roomId.isEmpty
                  ? null
                  : const Icon(CupertinoIcons.chevron_right, size: 18),
              onTap: record.roomId.isEmpty || record.isMultiRoom
                  ? null
                  : () => _open<void>(
                      context,
                      NeteaseTogetherRecordPage(
                        roomId: record.roomId,
                        peer: record.peer,
                        initialRecord: record,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.profile, {this.size = 48});
  final NeteaseTogetherProfile? profile;
  final double size;
  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox.square(
      dimension: size,
      child: profile?.avatar.isNotEmpty == true
          ? ArtworkImage(uri: profile!.avatar, width: size, height: size)
          : ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(CupertinoIcons.person_fill, size: size * .5),
            ),
    ),
  );
}

class _AvatarPair extends StatelessWidget {
  const _AvatarPair({this.self, this.peer});
  final NeteaseTogetherProfile? self, peer;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 114,
    height: 68,
    child: Stack(
      children: [
        _Avatar(self, size: 68),
        Positioned(left: 46, child: _Avatar(peer, size: 68)),
      ],
    ),
  );
}

class _RecordState extends StatelessWidget {
  const _RecordState({
    required this.busy,
    required this.error,
    required this.retry,
  });
  final bool busy;
  final String? error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) const BetaActivityIndicator(),
          if (error != null) ...[
            Text(error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            BetaGlassButton(
              onPressed: busy ? null : retry,
              child: const Text('重试'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _AccountChanged extends StatelessWidget {
  const _AccountChanged();
  @override
  Widget build(BuildContext context) => const PlatformPageFrame(
    title: '一起听记录',
    musicChrome: false,
    child: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('账号已变化，请返回后重新打开一起听记录'),
      ),
    ),
  );
}
