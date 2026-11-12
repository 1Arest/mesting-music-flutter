import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/persistence/app_preferences.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../../shared/models/song_list_memory.dart';
import '../../../shared/widgets/song_list_tools.dart';
import '../music_platform_providers.dart';
import '../platform_backend_providers.dart';

final songListMemoryProvider = Provider((ref) {
  final memory = SongListMemory(ref.watch(sharedPreferencesProvider));
  ref.onDispose(memory.dispose);
  return memory;
});

/// Account switches replace the inherited owner before another page callback
/// can write a bookmark. The persistent store is independent of audio services.
class SongListToolsHost extends ConsumerWidget {
  const SongListToolsHost({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!DistributionChannel.isBeta) return child;
    final account = ref.watch(platformAccountProvider).value;
    final netease = ref.watch(usesNeteaseProvider);
    return SongListOwnerScope(
      owner: account?.ownerId ?? 'guest:${netease ? 'netease' : 'kugou'}',
      memory: ref.watch(songListMemoryProvider),
      child: child,
    );
  }
}
