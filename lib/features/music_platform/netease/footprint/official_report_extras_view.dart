import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/platform/avatar_media_bridge.dart';
import '../../../../shared/media/artwork_network_image.dart';
import '../../../../shared/models/track.dart';
import '../../../../shared/widgets/artwork_image.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../player/presentation/beta_playback_actions.dart';
import 'official_report_extras.dart';
import 'official_record_wall.dart';

export 'official_record_wall.dart' show OfficialRecordWall;

/// Official values retain their own labels and percentages. They are never
/// reconstructed from the top three songs or the device's listening history.
class OfficialReportExtrasView extends ConsumerWidget {
  const OfficialReportExtrasView({
    required this.data,
    required this.period,
    required this.weekly,
    super.key,
  });
  final OfficialReportExtras data;
  final String period;
  final bool weekly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefix = weekly ? '本周' : '本月';
    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
    Widget ranked(
      List<OfficialReportItem> rows, {
      bool songs = false,
      bool artists = false,
    }) => LayoutBuilder(
      builder: (context, c) => Wrap(
        spacing: 12,
        runSpacing: 14,
        children: [
          for (final item in rows.take(3))
            SizedBox(
              width: (c.maxWidth - 24) / 3,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: !songs || item.id.isEmpty
                    ? null
                    : () => playBetaSelection(
                        context,
                        ref,
                        Track(
                          id: 'netease_${item.id}',
                          title: item.title,
                          artist: '',
                          album: '',
                          duration: Duration.zero,
                          audioAsset: '',
                          coverAsset: item.cover,
                          lyricsAsset: '',
                          source: TrackSource.netease,
                          platformSongId: item.id,
                        ),
                      ),
                child: Column(
                  children: [
                    if (item.detail.isNotEmpty)
                      Text(
                        item.detail,
                        maxLines: 3,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.fontFamily,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(artists ? 60 : 12),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ArtworkImage(
                          uri: item.cover,
                          fit: BoxFit.cover,
                          decodeWidth: 160,
                          decodeHeight: 160,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      item.title,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.fontFamily,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    Widget ratios(List<OfficialReportItem> rows) => Column(
      children: [
        for (final item in rows.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(item.title)),
                    if (item.percent != null)
                      Text(
                        '${item.percent!.toStringAsFixed(item.percent! % 1 == 0 ? 0 : 1)}%',
                      ),
                  ],
                ),
                if (item.percent != null) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      height: 8,
                      child: ColoredBox(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: item.percent! / 100,
                            heightFactor: 1,
                            child: ColoredBox(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
    return Column(
      key: const ValueKey('official-report-extras'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.achievement.isNotEmpty)
          section(
            '听歌印记',
            Column(
              children: [
                if (officialAchievementImages[data.achievement] case final url?)
                  SizedBox(
                    height: 120,
                    child: ArtworkImage(
                      uri: url,
                      fit: BoxFit.contain,
                      decodeWidth: 300,
                      decodeHeight: 300,
                    ),
                  )
                else
                  Icon(
                    CupertinoIcons.music_note_2,
                    color: Theme.of(context).colorScheme.primary,
                    size: 30,
                  ),
                const SizedBox(height: 8),
                Text(
                  data.achievement,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (data.achievementDetail.isNotEmpty)
                  Text(data.achievementDetail, textAlign: TextAlign.center),
              ],
            ),
          ),
        if (data.covers.isNotEmpty)
          section(
            '$prefix唱片墙',
            Column(
              children: [
                OfficialRecordWall(data: data, period: period),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (final wallpaper in [false, true])
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: wallpaper ? 0 : 10),
                          child: BetaGlassButton(
                            height: 44,
                            horizontalPadding: 8,
                            onPressed: () => showLiquidGlassBottomSheet<void>(
                              context: context,
                              useRootNavigator: true,
                              isScrollControlled: true,
                              builder: (_) => _RecordWallExport(
                                data: data,
                                period: period,
                                wallpaper: wallpaper,
                              ),
                            ),
                            child: Text(
                              wallpaper ? '生成壁纸' : '生成海报',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (data.songs.isNotEmpty)
          section('$prefix单曲', ranked(data.songs, songs: true)),
        if (data.artists.isNotEmpty)
          section('$prefix音乐人', ranked(data.artists, artists: true)),
        if (data.genres.isNotEmpty) section('$prefix曲风', ratios(data.genres)),
        if (data.ages.isNotEmpty) section('$prefix听歌年代', ranked(data.ages)),
        if (data.languages.isNotEmpty)
          section('$prefix听歌语言', ratios(data.languages)),
        const Padding(
          padding: EdgeInsets.only(top: 18),
          child: Text(
            '以上分析使用网易云官方报表；尚未返回的项目会在报表生成后显示。',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _RecordWallExport extends StatefulWidget {
  const _RecordWallExport({
    required this.data,
    required this.period,
    required this.wallpaper,
  });
  final OfficialReportExtras data;
  final String period;
  final bool wallpaper;
  @override
  State<_RecordWallExport> createState() => _RecordWallExportState();
}

class _RecordWallExportState extends State<_RecordWallExport> {
  final _capture = GlobalKey();
  bool _saving = false;
  String? _result;
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    ui.Image? image;
    try {
      // Decode public covers before capture. A failed image keeps its visible
      // placeholder and cannot stall saving forever or create fake artwork.
      await Future.wait(
        widget.data.covers
            .take(20)
            .map(
              (url) => precacheImage(
                ResizeImage.resizeIfNeeded(
                  240,
                  null,
                  networkArtworkProvider(url),
                ),
                context,
                onError: (_, _) {},
              ).timeout(const Duration(seconds: 8), onTimeout: () {}),
            ),
      );
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('图片生成失败');
      await AvatarMediaBridge.channel.invokeMethod<String>('saveImage', {
        'bytes': png.buffer.asUint8List(),
        'mimeType': 'image/png',
        'fileName':
            'mesting_official_report_${widget.wallpaper ? 'wallpaper' : 'poster'}.png',
      });
      if (mounted) setState(() => _result = '已保存到相册');
    } catch (_) {
      if (mounted) setState(() => _result = '保存失败，请稍后重试');
    } finally {
      image?.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .84,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              widget.wallpaper ? '唱片墙壁纸' : '唱片墙海报',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: RepaintBoundary(
                key: _capture,
                child: OfficialRecordWall(
                  data: widget.data,
                  period: widget.period,
                  wallpaper: widget.wallpaper,
                  animate: false,
                ),
              ),
            ),
          ),
          if (_result != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_result!)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: BetaGlassButton(
              blue: true,
              loading: _saving,
              onPressed: _save,
              child: const Text('保存到相册'),
            ),
          ),
        ],
      ),
    ),
  );
}
