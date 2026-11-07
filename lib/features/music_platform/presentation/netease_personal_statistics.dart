import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../domain/platform_session.dart';
import '../netease/netease_account_overview.dart';
import '../netease/netease_personal_connections_page.dart';
import '../netease/netease_user_providers.dart';
import '../netease/footprint/official_footprint.dart';
import '../netease/footprint/official_footprint_providers.dart';
import '../netease/footprint/official_footprint_reader.dart';
import '../netease/footprint/listening_footprint_page.dart';
import '../../themes/music_typography.dart';

/// Small independent subscription boundary: changes to relation totals or a
/// duration read never rebuild the long personal library or its glass layers.
class NeteasePersonalStatistics extends ConsumerStatefulWidget {
  const NeteasePersonalStatistics({required this.session, super.key});
  final PlatformSession session;
  @override
  ConsumerState<NeteasePersonalStatistics> createState() =>
      _NeteasePersonalStatisticsState();
}

class _NeteasePersonalStatisticsState
    extends ConsumerState<NeteasePersonalStatistics> {
  OfficialFootprintReader? _requestedReader;
  String? _requestDay;

  void _scheduleTotal(OfficialFootprintReader? reader) {
    if (reader == null || !TickerMode.valuesOf(context).enabled) return;
    final day = footprintDay(ref.read(officialFootprintClockProvider)());
    if (identical(reader, _requestedReader) && day == _requestDay) return;
    _requestedReader = reader;
    _requestDay = day;
    // Avoid changing a ChangeNotifier during the widget build. The account
    // provider disposes old readers and their late responses on a switch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          identical(reader, ref.read(officialFootprintReaderProvider))) {
        unawaited(reader.refreshTotalOnly());
      }
    });
  }

  void _push(Widget page) =>
      Navigator.of(context).push(betaContentRoute<void>(page));

  @override
  Widget build(BuildContext context) {
    final relations = ref.watch(neteasePersonalStatsProvider);
    final stats = relations.value?.ownerId == widget.session.ownerId
        ? relations.value
        : null;
    final overview = ref.watch(neteaseAccountOverviewProvider);
    final level = overview.isLoading ? null : overview.value?.level?.level;
    final reader = ref.watch(officialFootprintReaderProvider);
    _scheduleTotal(reader);
    Widget row() {
      final total = reader?.total;
      final seconds = total?.value;
      final durationHelp = seconds == null
          ? total?.failed == true
                ? '官方总时长读取失败，打开后重试'
                : '官方总时长尚未读取'
          : '官方总时长 ${officialDuration(seconds)}'
                '${total?.failed == true ? '，刷新失败，保留上次结果' : ''}';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          key: const ValueKey('netease-personal-statistics'),
          children: [
            _metric(
              'following',
              '${stats?.following ?? '—'}',
              '关注',
              relations.hasError ? '关注数读取失败，打开关注列表重试' : '查看关注',
              () => openNeteasePersonalConnections(
                context,
                ownerId: widget.session.ownerId,
                initialFollowers: false,
              ),
            ),
            _metric(
              'followers',
              '${stats?.followers ?? '—'}',
              '粉丝',
              relations.hasError ? '粉丝数读取失败，打开粉丝列表重试' : '查看粉丝',
              () => openNeteasePersonalConnections(
                context,
                ownerId: widget.session.ownerId,
                initialFollowers: true,
              ),
            ),
            _metric(
              'level',
              level == null ? 'Lv.—' : 'Lv.$level',
              '',
              '查看网易云等级',
              () => _push(const NeteaseAccountOverviewPage()),
            ),
            _metric(
              'duration',
              seconds == null ? '—' : '${seconds ~/ 3600}',
              '小时',
              durationHelp,
              () => _push(const NeteaseListeningFootprintPage()),
            ),
          ],
        ),
      );
    }

    return reader == null
        ? row()
        : ListenableBuilder(listenable: reader, builder: (_, _) => row());
  }

  Widget _metric(
    String id,
    String value,
    String unit,
    String help,
    VoidCallback action,
  ) => Expanded(
    child: Tooltip(
      message: help,
      child: Semantics(
        label: '$value $unit，$help',
        button: true,
        child: ExcludeSemantics(
          child: CupertinoButton(
            key: ValueKey('netease-personal-$id'),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
            onPressed: action,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      fontWeight: MusicTypography.titleWeight,
                    ),
                  ),
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: const TextStyle(
                        fontSize: MusicTypography.footnoteSize,
                      ),
                    ),
                ],
              ),
              style: TextStyle(
                fontSize: MusicTypography.bodySize,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    ),
  );
}
