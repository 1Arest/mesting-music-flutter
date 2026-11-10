import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/avatar_media_bridge.dart';
import '../../../core/platform/share_bridge.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../themes/music_typography.dart';
import 'song_share.dart';

Future<void> showSongShareSheet(BuildContext context, Track track) =>
    showLiquidGlassBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => SongShareSheet(track: track),
    );

class SongShareSheet extends StatefulWidget {
  const SongShareSheet({required this.track, super.key});
  final Track track;

  @override
  State<SongShareSheet> createState() => _SongShareSheetState();
}

class _SongShareSheetState extends State<SongShareSheet> {
  Uint8List? _poster;
  bool _busy = false;
  String? _message;

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error is PlatformException
              ? error.message ?? '操作失败，请重试'
              : '操作失败，请重试';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = songShareUrl(widget.track);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '分享歌曲',
                    style: TextStyle(
                      fontSize: MusicTypography.sectionTitleSize,
                      fontWeight: MusicTypography.titleWeight,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(CupertinoIcons.xmark),
                ),
              ],
            ),
            Text(
              '${widget.track.title} · ${widget.track.artist}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            if (_poster != null) ...[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.memory(
                      _poster!,
                      semanticLabel: '${widget.track.title}分享海报',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _perform(() async {
                        await AvatarMediaBridge.channel.invokeMethod<
                          String
                        >('saveImage', {
                          'bytes': _poster!,
                          'mimeType': 'image/png',
                          'fileName':
                              'mesting_song_${DateTime.now().millisecondsSinceEpoch}.png',
                        });
                        if (mounted) setState(() => _message = '海报已保存到相册');
                      }),
                icon: const Icon(CupertinoIcons.arrow_down_to_line),
                label: const Text('保存海报'),
              ),
            ] else
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _perform(() async {
                        final image = await generateSongPoster(widget.track);
                        if (mounted) setState(() => _poster = image);
                      }),
                icon: const Icon(CupertinoIcons.photo),
                label: const Text('生成分享海报'),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy || url == null
                  ? null
                  : () => _perform(() async {
                      await ShareBridge.shareToWeChat(url);
                    }),
              icon: const Icon(CupertinoIcons.chat_bubble_2),
              label: const Text('分享链接给微信好友'),
            ),
            if (url == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('这首歌暂无公开链接，可以生成海报分享。'),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(child: CupertinoActivityIndicator()),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _message!,
                  semanticsLabel: _message,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
