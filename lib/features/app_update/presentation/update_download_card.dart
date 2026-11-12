import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';

import '../../themes/beta_appearance.dart';
import '../../themes/music_typography.dart';
import '../app_update_providers.dart';
import 'apple_download_progress.dart';

/// Only this card subscribes to the bounded SDK telemetry stream. Release notes
/// and the premium glass sheet do not need a separate telemetry-driven rebuild.
class UpdateDownloadCard extends ConsumerWidget {
  const UpdateDownloadCard({required this.state, super.key});
  final AppUpdateState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => UpdateDownloadCardView(
    state: state,
    statistics: ref.watch(appUpdateStatisticsProvider).asData?.value,
  );
}

/// Presentation seam also used by layout/state tests. Payload rates are not an
/// acceleration multiplier, and a connected node alone is never called P2P.
class UpdateDownloadCardView extends StatefulWidget {
  const UpdateDownloadCardView({
    required this.state,
    this.statistics,
    super.key,
  });
  final AppUpdateState state;
  final RingTransferStatistics? statistics;

  @override
  State<UpdateDownloadCardView> createState() => _UpdateDownloadCardViewState();
}

class _UpdateDownloadCardViewState extends State<UpdateDownloadCardView> {
  bool _expanded = false;

  String _speed(double rate) => rate >= 1048576
      ? '${(rate / 1048576).toStringAsFixed(1)} MB/s'
      : '${(rate / 1024).toStringAsFixed(0)} KB/s';

  String _remaining(Duration? value) {
    if (value == null) return '剩余时间估算中';
    final seconds = (value.inMilliseconds / 1000).ceil();
    if (seconds < 60) return '预计剩余 ${seconds.clamp(1, 59)} 秒';
    if (seconds < 3600) return '预计剩余 ${(seconds / 60).ceil()} 分钟';
    return '预计剩余 ${(seconds / 3600).ceil()} 小时';
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final sample = widget.statistics;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final blue = BetaAppearance.accent(theme.brightness);
    final active =
        state.phase == AppUpdatePhase.downloading &&
        sample?.state == RingDownloadState.transferring &&
        sample?.cancelling != true;
    final available = sample?.available == true;
    final receiving = active && available ? sample!.receivingNodes : 0;
    final verified =
        (sample?.peerVerifiedBytes ?? 0) + (sample?.seedVerifiedBytes ?? 0);
    final p2p = receiving > 0 && verified > 0;
    final paused = state.phase == AppUpdatePhase.paused;
    final verifying = state.phase == AppUpdatePhase.verifying;
    final prepared = state.downloadedPath != null;
    final stopping = paused && sample?.cancelling == true;
    final title = prepared
        ? '安装包已校验'
        : verifying
        ? '正在校验安装包'
        : stopping
        ? '正在暂停下载'
        : paused
        ? '下载已暂停'
        : state.phase == AppUpdatePhase.failed
        ? '下载暂未完成'
        : p2p
        ? 'P2P 协同下载'
        : active && available && sample!.connectedNodes > 0
        ? '节点已连接 · 等待数据'
        : active && available && sample!.connectingNodes > 0
        ? '服务器下载 · 节点连接中'
        : '正在下载更新';
    final tint = p2p ? BetaAppearance.success(theme.brightness) : blue;
    final rate = active && available ? _speed(sample!.bytesPerSecond) : null;
    final hint = prepared
        ? '安装仍需系统确认'
        : verifying
        ? '确认文件完整性后，再继续安装'
        : stopping
        ? '正在保存进度并结束连接'
        : paused
        ? '进度已保存，可继续下载'
        : state.phase == AppUpdatePhase.failed
        ? '下载进度已保留'
        : _remaining(active && available ? sample!.estimatedRemaining : null);
    final detail = available ? '$receiving 路正在接收' : '传输详情暂不可用';
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return DecoratedBox(
      key: const ValueKey('update-download-card'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .48),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: .07)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  prepared
                      ? CupertinoIcons.checkmark_shield
                      : verifying
                      ? CupertinoIcons.shield
                      : p2p
                      ? Icons.hub_outlined
                      : paused
                      ? CupertinoIcons.pause_circle
                      : CupertinoIcons.arrow_down_circle,
                  color: tint,
                  size: 19,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: MusicTypography.subheadlineSize,
                      fontWeight: MusicTypography.titleWeight,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  state.progress == null
                      ? '—'
                      : '${(state.progress! * 100).round()}%',
                  style: TextStyle(
                    fontSize: MusicTypography.headingSize,
                    color: scheme.onSurface,
                    fontWeight: MusicTypography.titleWeight,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // The existing renderer preserves a resumed first frame and keeps
            // the percentage tied to actual file bytes, not transport payload.
            AppleDownloadProgress(
              key: const ValueKey('app-update-progress'),
              showLabels: false,
              receivedBytes: state.receivedBytes,
              totalBytes: state.totalBytes,
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  state.totalBytes > 0
                      ? '${formatDownloadBytes(state.receivedBytes)} / ${formatDownloadBytes(state.totalBytes)}'
                      : '已下载 ${formatDownloadBytes(state.receivedBytes)}',
                  style: TextStyle(
                    fontSize: MusicTypography.footnoteSize,
                    color: scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (rate != null)
                  Text(
                    rate,
                    key: const ValueKey('update-download-speed'),
                    style: TextStyle(
                      fontSize: MusicTypography.footnoteSize,
                      color: scheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  hint,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: MusicTypography.footnoteSize,
                  ),
                ),
                if (active && available)
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: MusicTypography.footnoteSize,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Semantics(
              button: true,
              expanded: _expanded,
              child: InkWell(
                key: const ValueKey('update-transfer-details-toggle'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _expanded = !_expanded),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '传输详情',
                          style: TextStyle(
                            fontSize: MusicTypography.footnoteSize,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),

                      const SizedBox(width: 7),
                      AnimatedRotation(
                        turns: _expanded ? .5 : 0,
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        child: Icon(
                          CupertinoIcons.chevron_down,
                          size: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              reverseDuration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !_expanded
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: !available
                          ? Text(
                              detail,
                              style: TextStyle(
                                fontSize: MusicTypography.footnoteSize,
                                color: scheme.onSurfaceVariant,
                              ),
                            )
                          : Column(
                              children: [
                                _source(
                                  context,
                                  CupertinoIcons.cloud_download,
                                  '服务器 HTTPS',
                                  active ? sample!.httpsBytesPerSecond : 0,
                                ),
                                _source(
                                  context,
                                  Icons.hub_outlined,
                                  '普通节点 · ${active ? sample!.nodes.where((n) => n.source == RingNodeSource.peer && n.state == RingNodeState.receiving).length : 0} 路',
                                  active ? sample!.peerBytesPerSecond : 0,
                                ),
                                _source(
                                  context,
                                  CupertinoIcons.leaf_arrow_circlepath,
                                  '种子节点 · ${active ? sample!.nodes.where((n) => n.source == RingNodeSource.seed && n.state == RingNodeState.receiving).length : 0} 路',
                                  active ? sample!.seedBytesPerSecond : 0,
                                ),
                              ],
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _source(
    BuildContext context,
    IconData icon,
    String label,
    double rate,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: MusicTypography.footnoteSize,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _speed(rate),
            style: TextStyle(
              fontSize: MusicTypography.footnoteSize,
              color: scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
