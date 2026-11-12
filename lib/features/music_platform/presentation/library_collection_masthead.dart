import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';
import 'platform_ranking_header.dart';

/// Library collections share public playlists' cover composition without
/// pretending that local history has remote comments or subscription counts.
class LibraryCollectionMasthead extends ConsumerWidget {
  const LibraryCollectionMasthead({
    required this.title,
    required this.cover,
    required this.total,
    this.toolbarActions = const [],
    this.actions = const [],
    this.countLabel,
    super.key,
  });
  final String title, cover;
  final int total;

  /// Streaming sources report the loaded window, never a fabricated total.
  final String? countLabel;
  final List<Widget> toolbarActions;
  final List<PlatformCollectionAction> actions;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(platformAccountProvider).value;
    return PlatformCollectionMasthead(
      title: title,
      platform: session?.platform ?? MusicPlatform.kugou,
      platformLabel: session?.platformLabel ?? '本机音乐库',
      cover: cover,
      period: '',
      secondary: countLabel ?? '$total 首歌曲',
      actions: actions,
      coverOnly: true,
      toolbarActions: toolbarActions,
    );
  }
}
