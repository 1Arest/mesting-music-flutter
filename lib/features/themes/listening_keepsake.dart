import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/platform/avatar_media_bridge.dart';
import '../history/listening_replay.dart';
import 'personal_style.dart';

/// Takes the existing account-owned replay aggregate, never creates synthetic
/// listening history or substitutes lifetime platform totals for this period.
Future<void> showListeningKeepsake(
  BuildContext context,
  ListeningReplay replay,
  int year,
  int? month,
) => showDialog<void>(
  context: context,
  builder: (_) => _KeepsakeDialog(replay: replay, year: year, month: month),
);

class _KeepsakeDialog extends ConsumerStatefulWidget {
  const _KeepsakeDialog({
    required this.replay,
    required this.year,
    required this.month,
  });
  final ListeningReplay replay;
  final int year;
  final int? month;
  @override
  ConsumerState<_KeepsakeDialog> createState() => _KeepsakeState();
}

class _KeepsakeState extends ConsumerState<_KeepsakeDialog> {
  final _image = GlobalKey();
  bool _busy = false;
  String? _message;
  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    ui.Image? image;
    try {
      final boundary =
          _image.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('无法生成纪念卡');
      await AvatarMediaBridge.channel.invokeMethod<String>('saveImage', {
        'bytes': data.buffer.asUint8List(),
        'mimeType': 'image/png',
        'fileName':
            'mesting_keepsake_${widget.year}_${widget.month ?? 'year'}.png',
      });
      if (mounted) setState(() => _message = '纪念卡已保存到相册');
    } catch (_) {
      if (mounted) setState(() => _message = '保存失败，请稍后重试');
    } finally {
      image?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final design = ref.watch(personalStyleProvider.select((s) => s.keepsake));

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                key: _image,
                child: ListeningKeepsakeCard(
                  design: design,
                  replay: widget.replay,
                  year: widget.year,
                  month: widget.month,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_alt),
                label: Text(_busy ? '正在保存' : '保存纪念卡'),
              ),
              if (_message != null) Text(_message!),
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The exact exported card, also used in the read-only style preview.
class ListeningKeepsakeCard extends StatelessWidget {
  const ListeningKeepsakeCard({
    required this.design,
    required this.replay,
    required this.year,
    this.month,
    this.preview = false,
    super.key,
  });
  final KeepsakeTemplate design;
  final ListeningReplay replay;
  final int year;
  final int? month;
  final bool preview;
  @override
  Widget build(BuildContext context) {
    final collection = design == KeepsakeTemplate.collection;
    final ink = collection ? const Color(0xFFDAC291) : const Color(0xFF25384C);
    return Container(
      width: 360,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: collection ? const Color(0xFF202124) : const Color(0xFFF4EEE1),
        border: Border.all(color: ink.withValues(alpha: .5), width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: ink,
          fontSize: 17,
          height: 1.5,
          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mesting Music', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 20),
            Text(
              design == KeepsakeTemplate.postcard
                  ? '听歌来信'
                  : collection
                  ? '音乐收藏卡'
                  : '听歌纪念卡',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            Text('$year 年${month == null ? ' · 全年' : ' · $month 月'}'),
            const SizedBox(height: 24),
            Center(
              child: Icon(
                collection
                    ? Icons.album_outlined
                    : Icons.mark_email_read_outlined,
                size: 90,
                color: ink,
              ),
            ),
            const SizedBox(height: 24),
            Text('音乐陪伴 ${replay.milliseconds ~/ 60000} 分钟'),
            Text('听过 ${replay.tracks.length} 首歌'),
            Text('相遇 ${replay.artists.length} 位歌手'),
            if (replay.tracks.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('本期常听'),
              Text(
                replay.tracks.first.track.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 24),
            const Text('把这段时光，收藏进旋律。'),
            const SizedBox(height: 12),
            Text(
              preview ? '示例预览 · 保存时使用你的实际记录' : '依据本机已有听歌记录生成',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
