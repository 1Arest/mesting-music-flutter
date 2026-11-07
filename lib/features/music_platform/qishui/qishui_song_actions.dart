import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../core/platform/share_bridge.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../downloads/audio_downloads_page.dart';
import '../../library/library_providers.dart';
import '../music_platform_providers.dart';

/// Soda has no path into SongMenuDetailsRepository's two legacy backends.
/// Every intent rechecks ownership after its sheet closes.
Future<void> showQishuiSongActions(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  List<(String, IconData, Future<void> Function())> extras = const [],
}) async {
  final account = ref.read(platformAccountProvider).value;
  final library = ref.read(libraryRepositoryProvider);
  final action = await showLiquidGlassBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (sheet) => SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(track.title, style: Theme.of(sheet).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('${track.artist} · 汽水音乐'),
          const SizedBox(height: 16),
          for (final item in const [
            ('play', Icons.play_arrow, '播放'),
            ('next', Icons.skip_next, '下一首播放'),
            ('queue', Icons.queue_music, '加入待播'),
            ('favorite', Icons.favorite_border, '喜欢／取消喜欢'),
            ('download', Icons.download, '下载'),
            ('share', Icons.share_outlined, '分享歌曲信息'),
          ])
            ListTile(
              leading: Icon(item.$2),
              title: Text(item.$3),
              onTap: () => Navigator.of(sheet).pop(item.$1),
            ),
          for (var i = 0; i < extras.length; i++)
            ListTile(
              leading: Icon(extras[i].$2),
              title: Text(extras[i].$1),
              onTap: () => Navigator.of(sheet).pop('extra:$i'),
            ),
        ],
      ),
    ),
  );
  if (action == null ||
      !context.mounted ||
      !identical(ref.read(platformAccountProvider).value, account)) {
    return;
  }
  try {
    final handler = ref.read(audioHandlerProvider);
    switch (action) {
      case 'play':
        await handler.playSingleTrack(
          track,
          isCurrent: () =>
              context.mounted &&
              ref.read(platformAccountProvider).value?.ownerId ==
                  account?.ownerId &&
              ref.read(platformAccountProvider).value?.token == account?.token,
        );
      case 'next':
        await handler.playNextInQueue(track);
      case 'queue':
        await handler.appendToUpcomingQueue(track);
      case 'favorite':
        await library.toggleFavorite(track);
      case 'download':
        await enqueueAudioDownload(context, ref, track);
      case 'share':
        await ShareBridge.shareText('${track.title} — ${track.artist}（汽水音乐）');
      default:
        if (action.startsWith('extra:')) {
          await extras[int.parse(action.substring(6))].$3();
        }
    }
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}
